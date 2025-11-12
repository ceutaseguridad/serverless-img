#!/bin/bash

# ==============================================================================
# Script de Arranque v20 (LA VERSIÓN CORRECTA FINAL)
# Basado en la prueba irrefutable de 'df -h'. El volumen está en /workspace.
# ==============================================================================

set -e
set -o pipefail

# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias..."
apt-get update > /dev/null 2>&1 && apt-get install -y curl > /dev/null 2>&1
pip install insightface onnxruntime-gpu facexlib timm ftfy > /dev/null 2>&1
echo "[MORPHEUS-STARTUP]    -> Dependencias instaladas."

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v20 (LA VERSIÓN CORRECTA) ---"
echo "====================================================================="

# --- FASE 2: DEFINICIÓN DE RUTAS BASADAS EN LA REALIDAD ---
# El volumen de red PERSISTENTE está montado en /workspace.
NETWORK_VOLUME_PATH="/workspace"

# El código fuente también se clona en una subcarpeta de /workspace.
CONFIG_SOURCE_DIR="${NETWORK_VOLUME_PATH}/morpheus_config" 

# Todas las rutas persistentes derivan de /workspace.
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"

# Rutas internas de ComfyUI en el disco efímero (esto no cambia).
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"

echo "[MORPHEUS-STARTUP] FASE 2: Rutas definidas."
echo "[MORPHEUS-STARTUP]    -> Volumen Persistente: ${NETWORK_VOLUME_PATH}"
echo "[MORPHEUS-STARTUP]    -> Caché de Modelos: ${CACHE_DIR}"

# --- FASE 3: VERIFICACIÓN DEL VOLUMEN ---
# Aunque ya está montado, esperamos para evitar cualquier race condition.
echo "[MORPHEUS-STARTUP] FASE 3: Verificando que '${CACHE_DIR}' es visible..."
WAIT_TIMEOUT=30; ELAPSED=0
while [ ! -d "$CACHE_DIR" ]; do
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció."; exit 1; fi
    echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2))
done
echo " ¡Volumen persistente verificado en /workspace!"

# --- FASE 4: PREPARACIÓN DEL ENTORNO ---
mkdir -p "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "[MORPHEUS-STARTUP]    -> Workflows copiados a '${WORKFLOWS_DEST_DIR}'."

cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"
echo "[MORPHEUS-STARTUP]    -> Handler de ComfyUI copiado."

RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
echo "[MORPHEUS-STARTUP] FASE 4: Creando enlaces simbólicos..."
while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs)
    case "$type" in
        GIT)
            SOURCE_PATH="${CACHE_DIR}/${name}"; DEST_PATH="${CUSTOM_NODES_DIR}/${name}"; if [ -d "$SOURCE_PATH" ]; then ln -sf "${SOURCE_PATH}" "${DEST_PATH}"; fi ;;
        URL_AUTH)
            MODEL_FOLDER=$(dirname "${name}"); SOURCE_PATH="${CACHE_DIR}/${MODEL_FOLDER}"; DEST_PATH="${MODELS_DIR}/${MODEL_FOLDER}"; if [ -d "$SOURCE_PATH" ]; then mkdir -p "$(dirname "${DEST_PATH}")"; ln -sfn "${SOURCE_PATH}" "${DEST_PATH}"; fi ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++')
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
