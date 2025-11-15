#!/bin/bash

# ==============================================================================
# Script de Arranque v21 (Basado en la Prueba del Señuelo)
# ==============================================================================

set -e
set -o pipefail

# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS (VERSIÓN FINAL, COJONES) ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias..."
apt-get update > /dev/null 2>&1 && apt-get install -y curl > /dev/null 2>&1

# --- INICIO DE LA PUTA CORRECCIÓN FINAL ---
# 1. Forzamos la instalación de la versión correcta de insightface, ignorando la caché.
echo "[MORPHEUS-STARTUP]    -> Forzando instalación de insightface v0.7.3..."
pip install --no-cache-dir --force-reinstall insightface==0.7.3

# 2. Instalamos el resto de dependencias del handler.
echo "[MORPHEUS-STARTUP]    -> Instalando dependencias del handler..."
pip install onnxruntime-gpu facexlib timm ftfy requests > /dev/null 2>&1

# 3. Instalamos xformers para optimizar la VRAM y eliminar la advertencia.
echo "[MORPHEUS-STARTUP]    -> Instalando xformers para optimización..."
pip install xformers
# --- FIN DE LA PUTA CORRECCIÓN FINAL ---

echo "[MORPHEUS-STARTUP]    -> Dependencias instaladas."

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v21 (Verificada) ---"
echo "====================================================================="

# --- FASE 2: DEFINICIÓN DE RUTAS ---
# El código fuente vive en el disco EFÍMERO /workspace.
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 

# El volumen de red PERSISTENTE se ve en /runpod-volume.
NETWORK_VOLUME_PATH="/runpod-volume"

# Todas las rutas persistentes derivan de /runpod-volume.
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"

# Rutas internas de ComfyUI.
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"

echo "[MORPHEUS-STARTUP] FASE 2: Rutas definidas para el worker."
echo "[MORPHEUS-STARTUP]    -> Volumen Persistente: ${NETWORK_VOLUME_PATH}"
echo "[MORPHEUS-STARTUP]    -> Caché de Modelos: ${CACHE_DIR}"

# --- FASE 3: ESPERA Y VERIFICACIÓN DEL VOLUMEN ---
echo "[MORPHEUS-STARTUP] FASE 3: Esperando que '${CACHE_DIR}' sea visible..."
WAIT_TIMEOUT=60; ELAPSED=0
while [ ! -d "$CACHE_DIR" ]; do
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció."; exit 1; fi
    echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2))
done
echo " ¡Volumen persistente verificado en /runpod-volume!"

# --- [INICIO DE LA MODIFICACIÓN DE DEPURACIÓN] ---
# --- FASE 4: PREPARACIÓN DEL ENTORNO ---
echo "[MORPHEUS-STARTUP] FASE 4: Preparando entorno de workflows..."

# Paso de depuración: Listar lo que ve el script ANTES de copiar
echo "[MORPHEUS-STARTUP]    -> Contenido detectado en ${CONFIG_SOURCE_DIR}/workflows/:"
ls -l "${CONFIG_SOURCE_DIR}/workflows/"

# El comando de copia
mkdir -p "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "[MORPHEUS-STARTUP]    -> Workflows copiados a '${WORKFLOWS_DEST_DIR}'."

# Paso de depuración: Listar lo que se ha copiado DESPUÉS
echo "[MORPHEUS-STARTUP]    -> Contenido verificado en ${WORKFLOWS_DEST_DIR}/:"
ls -l "${WORKFLOWS_DEST_DIR}/"
# --- [FIN DE LA MODIFICACIÓN DE DEPURACIÓN] ---

cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"
echo "[MORPHEUS-STARTUP]    -> Handler de ComfyUI copiado."

RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
# ==============================================================================
# BLOQUE DE VERIFICACIÓN DE RUTA - INICIO
# ==============================================================================
echo "--- INICIO VERIFICACIÓN DE RECURSOS (TAREA SIMPLE) ---"
echo "El script va a leer la lista de nodos desde esta ruta exacta:"
echo "    -> ${RESOURCE_FILE}"
echo ""
echo "Comprobando si el fichero existe en esa ruta..."
ls -l "${RESOURCE_FILE}" || echo "    -> ERROR: El fichero NO EXISTE en la ruta especificada."
echo ""
echo "Contenido del fichero que se va a leer:"
echo "----------------------------------------------------"
cat "${RESOURCE_FILE}" || echo "    -> ERROR: No se pudo leer el contenido del fichero."
echo "----------------------------------------------------"
echo "--- FIN VERIFICACIÓN DE RECURSOS ---"
# ==============================================================================
# BLOQUE DE VERIFICACIÓN DE RUTA - FIN
# ==============================================================================

echo "[MORPHEUS-STARTUP] FASE 4: Creando enlaces simbólicos..."
while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs)
    case "$type" in
        GIT)
            # Esto ya estaba bien
            SOURCE_PATH="${CACHE_DIR}/${name}"; DEST_PATH="${CUSTOM_NODES_DIR}/${name}";
            if [ -d "$SOURCE_PATH" ]; then ln -sf "${SOURCE_PATH}" "${DEST_PATH}"; fi ;;
        URL_AUTH)
            # [LA CORRECCIÓN FINAL]
            # Ahora enlazamos el ARCHIVO, no la CARPETA.
            MODEL_FOLDER=$(dirname "${name}");
            MODEL_FILENAME=$(basename "${name}");
            SOURCE_FILE_PATH="${CACHE_DIR}/${MODEL_FOLDER}/${MODEL_FILENAME}";
            DEST_FOLDER_PATH="${MODELS_DIR}/${MODEL_FOLDER}";

            if [ -f "$SOURCE_FILE_PATH" ]; then
                mkdir -p "$DEST_FOLDER_PATH";
                ln -sf "$SOURCE_FILE_PATH" "$DEST_FOLDER_PATH";
            fi ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++')

# --- INICIO DE LA CORRECCIÓN ESPECÍFICA PARA PuLID ---
echo "[MORPHEUS-STARTUP]    -> Creando enlace específico para el modelo PuLID..."
mkdir -p "${MODELS_DIR}/pulid/"
ln -sf "${CACHE_DIR}/checkpoints/pulid_v1.1.safetensors" "${MODELS_DIR}/pulid/"
# --- FIN DE LA CORRECCIÓN ESPECÍFICA PARA PuLID ---

echo "[MORPHEUS-STARTUP]    -> Enlaces completados."
# --- FASE 5: INICIO DE SERVICIOS ---
echo "[MORPHEUS-STARTUP] FASE 5: Iniciando servicios..."
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 --verbose &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado."

TIMEOUT=180; ELAPSED=0
while true; do
    if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then echo; echo "[MORPHEUS-STARTUP] -> ¡Servidor de ComfyUI está listo!"; break; else echo -n "."; fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió."; exit 1; fi
    sleep 3; ELAPSED=$((ELAPSED + 3))
done

echo "====================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"
echo "====================================================================="

# --- FASE 6: INICIO DEL HANDLER DE MORPHEUS ---
cd "${CONFIG_SOURCE_DIR}"
echo "[MORPHEUS-STARTUP] Iniciando el handler 'morpheus_handler.py'..."
exec python3 -u morpheus_handler.py
