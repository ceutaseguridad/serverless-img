#!/bin/bash

# ==============================================================================
# Script de Arranque v17 (Con Agua Bendita y Rutas Correctas)
# Premisa: El volumen persistente SIEMPRE es /runpod-volume en Serverless.
# ==============================================================================

set -e
set -o pipefail

# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias de Python..."
# Se instalan las dependencias necesarias para los nodos personalizados.
apt-get update > /dev/null 2>&1 && apt-get install -y curl > /dev/null 2>&1
pip install insightface onnxruntime-gpu facexlib timm ftfy > /dev/null 2>&1
echo "[MORPHEUS-STARTUP]    -> Dependencias instaladas."

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v17 (Rutas Definitivas) ---"
echo "====================================================================="

# --- FASE 2: DEFINICIÓN DE RUTAS ---
# El código fuente clonado por RunPod vive en el disco EFÍMERO /workspace.
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 

# El volumen de red PERSISTENTE se monta en /runpod-volume.
NETWORK_VOLUME_PATH="/runpod-volume"

# Rutas que dependen del volumen PERSISTENTE.
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"

# Rutas internas de ComfyUI en el disco efímero.
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"

echo "[MORPHEUS-STARTUP] FASE 2: Rutas definidas."
echo "[MORPHEUS-STARTUP]    -> Origen de Configuración (efímero): ${CONFIG_SOURCE_DIR}"
echo "[MORPHEUS-STARTUP]    -> Volumen de Red (persistente): ${NETWORK_VOLUME_PATH}"
echo "[MORPHEUS-STARTUP]    -> Caché de Modelos (persistente): ${CACHE_DIR}"

# --- FASE 3: ESPERA Y VERIFICACIÓN DEL VOLUMEN DE RED ---
echo "[MORPHEUS-STARTUP] FASE 3: Esperando a que el volumen de red se monte..."
WAIT_TIMEOUT=30
ELAPSED=0
while [ ! -d "$CACHE_DIR" ]; do
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "¡ERROR FATAL! El directorio del caché '${CACHE_DIR}' no apareció después de ${WAIT_TIMEOUT} segundos."
        echo "Verifica que el Network Volume está correctamente asociado y la ruta es correcta."
        exit 1
    fi
    echo -n "."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
echo " ¡Volumen persistente montado y verificado!"

# --- FASE 4: PREPARACIÓN DEL ENTORNO ---
# Copiamos los workflows desde el código efímero al almacenamiento persistente para que el handler los encuentre.
mkdir -p "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "[MORPHEUS-STARTUP]    -> Workflows copiados a '${WORKFLOWS_DEST_DIR}'."

# Copiamos el handler de ComfyUI para asegurar que la importación en Python funcione.
cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"
echo "[MORPHEUS-STARTUP]    -> Handler de ComfyUI copiado para importación."

# Creamos los enlaces simbólicos desde el disco efímero de ComfyUI al caché de modelos persistente.
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
echo "[MORPHEUS-STARTUP] FASE 4: Creando enlaces simbólicos desde '${CACHE_DIR}'..."
while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs)
    case "$type" in
        GIT)
            SOURCE_PATH="${CACHE_DIR}/${name}"; DEST_PATH="${CUSTOM_NODES_DIR}/${name}"
            if [ -d "$SOURCE_PATH" ]; then ln -sf "${SOURCE_PATH}" "${DEST_PATH}"; fi
            ;;
        URL_AUTH)
            MODEL_FOLDER=$(dirname "${name}"); SOURCE_PATH="${CACHE_DIR}/${MODEL_FOLDER}"; DEST_PATH="${MODELS_DIR}/${MODEL_FOLDER}"
            if [ -d "$SOURCE_PATH" ]; then mkdir -p "$(dirname "${DEST_PATH}")"; ln -sfn "${SOURCE_PATH}" "${DEST_PATH}"; fi
            ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++')
echo "[MORPHEUS-STARTUP]    -> Enlaces completados."

# --- FASE 5: INICIO DE SERVICIOS ---
echo "[MORPHEUS-STARTUP] FASE 5: Iniciando servicios en segundo plano..."
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado. Esperando health check..."

TIMEOUT=180; ELAPSED=0
while true; do
    if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then
        echo; echo "[MORPHEUS-STARTUP]    -> ¡Servidor de ComfyUI está listo!"; break
    else
        echo -n "."
    fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió en ${TIMEOUT}s."; exit 1; fi
    sleep 3; ELAPSED=$((ELAPSED + 3))
done

echo "====================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"
echo "====================================================================="

# --- FASE 6: INICIO DEL HANDLER DE MORPHEUS ---
# Nos movemos al directorio del código fuente para que las importaciones funcionen.
cd "${CONFIG_SOURCE_DIR}"
echo "[MORPHEUS-STARTUP] Iniciando el handler 'morpheus_handler.py'..."
# 'exec' reemplaza el proceso del script con el de Python, que es lo que RunPod espera.
exec python3 -u morpheus_handler.py
