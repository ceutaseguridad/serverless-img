#!/bin/bash

# ==============================================================================
# Script de Arranque v23 (con Parche Automatizado y Rutas Verificadas)
# ==============================================================================

set -e
set -o pipefail

# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias..."
apt-get update > /dev/null 2>&1 && apt-get install -y build-essential python3-dev curl unzip > /dev/null 2>&1

echo "[MORPHEUS-STARTUP]    -> Forzando instalación de insightface v0.7.3..."
pip install --upgrade --no-cache-dir --force-reinstall insightface==0.7.3 onnxruntime-gpu facexlib timm ftfy requests xformers "huggingface-hub<1.0"
echo "[MORPHEUS-STARTUP]    -> Dependencias instaladas."

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v23 (Verificada) ---"
echo "====================================================================="

# --- FASE 2: DEFINICIÓN DE RUTAS ---
# Ruta del código fuente efímero del worker
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 

# Ruta del volumen de red persistente TAL COMO LO VE EL WORKER
NETWORK_VOLUME_PATH="/runpod-volume"

# Rutas clave derivadas del volumen persistente
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"

# Rutas internas de ComfyUI en el disco efímero del worker
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"

echo "[MORPHEUS-STARTUP] FASE 2: Rutas definidas para el worker."
echo "[MORPHEUS-STARTUP]    -> Volumen Persistente (visto como): ${NETWORK_VOLUME_PATH}"
echo "[MORPHEUS-STARTUP]    -> Caché de Modelos: ${CACHE_DIR}"

# --- FASE 3: ESPERA Y VERIFICACIÓN DEL VOLUMEN ---
echo "[MORPHEUS-STARTUP] FASE 3: Esperando que '${CACHE_DIR}' sea visible..."
# ... (El resto del script de espera es correcto)
WAIT_TIMEOUT=60; ELAPSED=0
while [ ! -d "$CACHE_DIR" ]; do
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció."; exit 1; fi
    echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2))
done
echo " ¡Volumen persistente verificado en /runpod-volume!"

# --- FASE 4: PREPARACIÓN DEL ENTORNO Y ENLACES ---
# ... (El resto de esta sección es correcta)
echo "[MORPHEUS-STARTUP] FASE 4: Preparando entorno y creando enlaces simbólicos..."
mkdir -p "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"

RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs)
    case "$type" in
        GIT)
            SOURCE_PATH="${CACHE_DIR}/${name}"; DEST_PATH="${CUSTOM_NODES_DIR}/${name}";
            if [ -d "$SOURCE_PATH" ]; then ln -sf "${SOURCE_PATH}" "${DEST_PATH}"; fi ;;
        URL_AUTH)
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

mkdir -p "${MODELS_DIR}/pulid/"
ln -sf "${CACHE_DIR}/checkpoints/pulid_v1.1.safetensors" "${MODELS_DIR}/pulid/"
echo "[MORPHEUS-STARTUP]    -> Enlaces completados."

# ==============================================================================
# FASE 4.5: APLICACIÓN DE PARCHES EN CALIENTE (VERSIÓN CORREGIDA)
# ==============================================================================
# Esta sección modifica archivos de código fuente en el VOLUMEN PERSISTENTE
# desde el worker, utilizando la ruta correcta que este ve (/runpod-volume).

# La ruta al archivo pulid.py en el almacenamiento persistente, vista desde el worker.
# Corresponde a /workspace/morpheus_model_cache/ComfyUI-PuLID/pulid.py en el Pod.
PULID_PY_PATH_ON_WORKER="${CACHE_DIR}/ComfyUI-PuLID/pulid.py"

echo "[MORPHEUS-STARTUP] FASE 4.5: Aplicando parches..."
echo "[MORPHEUS-STARTUP]    -> Buscando archivo a parchear en: ${PULID_PY_PATH_ON_WORKER}"

if [ -f "$PULID_PY_PATH_ON_WORKER" ]; then
    if grep -q 'name="buffalo_l"' "$PULID_PY_PATH_ON_WORKER"; then
        echo "[MORPHEUS-STARTUP]    -> PARCHE VERIFICADO: El archivo ya está modificado. No se requieren acciones."
    else
        echo "[MORPHEUS-STARTUP]    -> Archivo encontrado. Aplicando parche para InsightFace..."
        sed -i 's/name="antelopev2"/name="buffalo_l"/' "$PULID_PY_PATH_ON_WORKER"
        echo "[MORPHEUS-STARTUP]    -> ¡ÉXITO! El parche se ha aplicado al archivo en el volumen persistente."
    fi
else
    echo "[MORPHEUS-STARTUP]    -> ADVERTENCIA: No se encontró '$PULID_PY_PATH_ON_WORKER'. Se omite el parche. El sistema podría fallar."
fi
# ==============================================================================
# FIN DE LA SECCIÓN DE PARCHES
# ==============================================================================

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
