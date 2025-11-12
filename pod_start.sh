#!/bin/bash

# ==============================================================================
# Script de Arranque v16 (Con Espera de Montaje de Volumen)
# ==============================================================================

set -e
set -o pipefail

# --- FASE 1: (Sin cambios) ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias..."
apt-get update && apt-get install -y curl
pip install insightface onnxruntime-gpu facexlib timm ftfy
echo "[MORPHEUS-STARTUP]    -> Dependencias completas instaladas."

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v16 (Espera de Montaje) ---"
echo "====================================================================="

# --- FASE 2: CONFIGURACIÓN DE RUTAS (Sin cambios) ---
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 
cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"
echo "[MORPHEUS-STARTUP]    -> Handler original copiado."

COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
NETWORK_VOLUME_PATH="/workspace"
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"

# --- [NUEVO BLOQUE DE ESPERA] ---
# Forzamos al script a esperar a que el volumen de red esté realmente montado y visible.
echo "[MORPHEUS-STARTUP] Esperando a que el volumen de red se monte en '${CACHE_DIR}'..."
WAIT_TIMEOUT=30
ELAPSED=0
while [ ! -d "$CACHE_DIR" ]; do
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "¡ERROR FATAL! El directorio del caché no apareció después de ${WAIT_TIMEOUT} segundos."
        exit 1
    fi
    echo -n "."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done
echo " ¡Volumen montado!"
# --- FIN DEL NUEVO BLOQUE ---

# La comprobación original ahora funcionará porque hemos esperado
if [ ! -d "$CACHE_DIR" ]; then 
    echo "¡ERROR FATAL! Caché no encontrado en '${CACHE_DIR}'. Verifica la ruta."; 
    exit 1; 
fi
echo "[MORPHEUS-STARTUP]    -> Directorio de caché encontrado en '${CACHE_DIR}'."

mkdir -p "${CUSTOM_NODES_DIR}" "${MODELS_DIR}" "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "[MORPHEUS-STARTUP]    -> Workflows copiados."

# --- FASE 3, 4 y 5 (Sin cambios) ---
# (El resto del script es idéntico al anterior)
echo "[MORPHEUS-STARTUP] FASE 3: Creando enlaces simbólicos..."
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

echo "[MORPHEUS-STARTUP] FASE 4: Iniciando servicios..."
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado. Esperando..."

TIMEOUT=180; ELAPSED=0
while true; do
    if curl -s --head http://12-7.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then
        echo; echo "[MORPHEUS-STARTUP]    -> ¡Servidor de ComfyUI está listo!"; break
    else
        echo -n "."
    fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió."; exit 1; fi
    sleep 3; ELAPSED=$((ELAPSED + 3))
done

echo "====================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"
echo "====================================================================="

echo "[MORPHEUS-STARTUP] Iniciando el handler personalizado de Morpheus..."
cd "${CONFIG_SOURCE_DIR}"
exec python3 -u morpheus_handler.py
