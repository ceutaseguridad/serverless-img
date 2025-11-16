#!/bin/bash

# ==============================================================================
# Script de Arranque v26 (Final, Completo y Fiel al Original)
# ==============================================================================

set -e
set -o pipefail

# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias..."
apt-get update > /dev/null 2>&1 && apt-get install -y build-essential python3-dev curl unzip git > /dev/null 2>&1

echo "[MORPHEUS-STARTUP]    -> Forzando instalación de dependencias base..."
pip install --upgrade --no-cache-dir --force-reinstall insightface==0.7.3 facexlib timm ftfy requests xformers "huggingface-hub<1.0"
echo "[MORPHEUS-STARTUP]    -> Dependencias base instaladas."

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v26 ---"
echo "====================================================================="

# --- FASE 2: DEFINICIÓN DE RUTAS (ORIGINAL) ---
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 
NETWORK_VOLUME_PATH="/runpod-volume"
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
echo "[MORPHEUS-STARTUP] FASE 2: Rutas definidas."

# --- FASE 3: VERIFICACIÓN DEL VOLUMEN (ORIGINAL) ---
echo "[MORPHEUS-STARTUP] FASE 3: Esperando volumen persistente..."
WAIT_TIMEOUT=60; ELAPSED=0
while [ ! -d "$CACHE_DIR" ]; do
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció."; exit 1; fi
    echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2))
done
echo " ¡Volumen persistente verificado!"

# --- FASE 4: PREPARACIÓN DEL ENTORNO Y ENLACES (ORIGINAL) ---
echo "[MORPHEUS-STARTUP] FASE 4: Preparando entorno y creando enlaces simbólicos..."
mkdir -p "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"

RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs);
    SOURCE_PATH="${CACHE_DIR}/${name}"
    case "$type" in
        GIT)
            DEST_PATH="${CUSTOM_NODES_DIR}/${name}";
            if [ -d "$SOURCE_PATH" ]; then ln -sf "${SOURCE_PATH}" "${DEST_PATH}"; fi ;;
        URL_AUTH)
            # Tu lógica original para URL_AUTH que asume archivos individuales
            MODEL_FOLDER=$(dirname "${name}");
            MODEL_FILENAME=$(basename "${name}");
            SOURCE_FILE_PATH="${CACHE_DIR}/${MODEL_FOLDER}/${MODEL_FILENAME}";
            DEST_FOLDER_PATH="${MODELS_DIR}/${MODEL_FOLDER}";
            if [ -f "$SOURCE_FILE_PATH" ]; then
                mkdir -p "$DEST_FOLDER_PATH";
                ln -sf "$SOURCE_FILE_PATH" "$DEST_FOLDER_PATH";
            # Adaptación para enlazar carpetas enteras como insightface, ipadapter, controlnet
            elif [ -d "$SOURCE_PATH" ]; then
                DEST_PATH="${MODELS_DIR}/${name}";
                mkdir -p "$(dirname "$DEST_PATH")";
                ln -sf "$SOURCE_PATH" "$DEST_PATH";
            fi ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++')

echo "[MORPHEUS-STARTUP]    -> Enlaces completados."

# ==============================================================================
# FASE 4.5: APLICACIÓN DE PARCHES EN CALIENTE (RE-INTRODUCIDO)
# ==============================================================================
PULID_PY_PATH="${CACHE_DIR}/ComfyUI-PuLID/pulid.py"
echo "[MORPHEUS-STARTUP] FASE 4.5: Aplicando parche de retrocompatibilidad para PuLID..."
if [ -f "$PULID_PY_PATH" ]; then
    sed -i 's/name="antelopev2"/name="buffalo_l"/' "$PULID_PY_PATH"
    echo "[MORPHEUS-STARTUP]    -> Parche para PuLID aplicado."
else
    echo "[MORPHEUS-STARTUP]    -> ADVERTENCIA: No se encontró 'pulid.py'. Se omite el parche."
fi
# ==============================================================================

# ==============================================================================
# FASE 4.6: INSTALAR DEPENDENCIAS DE NODOS PERSONALIZADOS
# ==============================================================================
echo "[MORPHEUS-STARTUP] FASE 4.6: Instalando dependencias de nodos personalizados..."
for req_file in $(find "${CUSTOM_NODES_DIR}" -maxdepth 2 -name "requirements.txt"); do
    node_name=$(basename $(dirname "$req_file"))
    echo "[MORPHEUS-STARTUP]    -> Instalando dependencias para el nodo '${node_name}'..."
    pip install -r "$req_file"
done
echo "[MORPHEUS-STARTUP]    -> Dependencias de nodos finalizadas."
# ==============================================================================

# --- FASE 5: INICIO DE SERVICIOS (ORIGINAL) ---
echo "[MORPHEUS-STARTUP] FASE 5: Iniciando servicios..."
# ... (El resto del script es idéntico al original)
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 --verbose &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado."
TIMEOUT=180; ELAPSED=0
while true; do
    if curl -s --head http://1227.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then echo; echo "[MORPHEUS-STARTUP] -> ¡Servidor de ComfyUI está listo!"; break; else echo -n "."; fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió."; exit 1; fi
    sleep 3; ELAPSED=$((ELAPSED + 3))
done
echo "====================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"
echo "====================================================================="

# --- FASE 6: INICIO DEL HANDLER DE MORPHEUS (ORIGINAL) ---
cd "${CONFIG_SOURCE_DIR}"
echo "[MORPHEUS-STARTUP] Iniciando el handler 'morpheus_handler.py'..."
exec python3 -u morpheus_handler.py
