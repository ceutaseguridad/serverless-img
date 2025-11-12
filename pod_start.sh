#!/bin/bash

# ==============================================================================
# Script de Arranque v14 (Impecable) para Morpheus AI Suite
# ==============================================================================

set -e
set -o pipefail

# --- FASE 1: INSTALACIÓN COMPLETA DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias..."
apt-get update && apt-get install -y curl
# [CORRECCIÓN FINAL] Añadimos 'ftfy', la última dependencia descubierta para PuLID.
pip install insightface onnxruntime-gpu facexlib timm ftfy
echo "[MORPHEUS-STARTUP]    -> Dependencias completas instaladas."

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v14 (IMPECABLE)    ---"
echo "====================================================================="

# --- FASE 2: CONFIGURACIÓN DE RUTAS Y ENTORNO ---
CONFIG_SOURCE_DIR="/workspace/morpheus_config"
cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"
echo "[MORPHEUS-STARTUP]    -> Handler original copiado para asegurar la importación."

COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
NETWORK_VOLUME_PATH="/runpod-volume"
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"

if [ ! -d "$CACHE_DIR" ]; then echo "¡ERROR FATAL! Caché no encontrado."; exit 1; fi
echo "[MORPHEUS-STARTUP]    -> Directorio de caché encontrado."

mkdir -p "${CUSTOM_NODES_DIR}" "${MODELS_DIR}" "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "[MORPHEUS-STARTUP]    -> Workflows copiados."

# --- FASE 3: ENLACE SIMBÓLICO DESDE EL CACHÉ ---
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

# --- FASE 4: INICIO DE SERVICIOS ---
echo "[MORPHEUS-STARTUP] FASE 4: Iniciando servicios..."
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado. Esperando..."

# Health Check
TIMEOUT=180; ELAPSED=0
while true; do
    if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then
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

# --- FASE 5: INICIO DEL HANDLER PERSONALIZADO ---
echo "[MORP-STARTUP] Iniciando el handler personalizado de Morpheus..."
cd "${CONFIG_SOURCE_DIR}"

# EJECUTAMOS el handler y lo ponemos en segundo plano
python3 -u morpheus_handler.py &

# ESPERAMOS a que CUALQUIER proceso en segundo plano termine (ComfyUI o el handler)
wait -n

# Capturamos el código de salida y terminamos
exit $?
