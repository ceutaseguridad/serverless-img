#!/bin/bash

# ==============================================================================
# Script de Arranque v33.1 (Solución de Mínima Invasión + Logs Únicos + Corrección de Sintaxis)
# ==============================================================================

# No usamos 'set -e' para que el script no muera y podamos registrar el error.
# set -e
set -o pipefail

# --- FASE 0: PREPARACIÓN DE LOGS ÚNICOS ---
NETWORK_VOLUME_PATH="/runpod-volume"
# Crea un nombre de fichero único usando la fecha y hora hasta los nanosegundos
UNIQUE_ID=$(date +%Y%m%d_%H%M%S_%N)
MASTER_LOG_FILE="${NETWORK_VOLUME_PATH}/log_${UNIQUE_ID}.txt"

# Usamos 'exec' para redirigir TODA la salida del script (stdout y stderr) a nuestro log.
# Esto es más robusto que añadir '>> $LOG' a cada línea.
exec > >(tee -a "${MASTER_LOG_FILE}") 2>&1

echo "--- INICIO DEL LOG DE MÍNIMA INVASIÓN (ID: ${UNIQUE_ID}) ---"
echo "====================================================================="


# --- FASE 1: INSTALACIÓN MÍNIMA ---
echo "[INFO] FASE 1: Instalando dependencias del sistema y de la aplicación..."
apt-get update && apt-get install -y build-essential python3-dev curl unzip git
pip install --upgrade pip
pip install --no-cache-dir insightface==0.7.3 facexlib timm ftfy

# --- FASES 2, 3 Y 4 ---
echo "[INFO] FASE 2: Definiendo rutas..."
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 
NETWORK_VOLUME_PATH="/runpod-volume"
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"

echo "[INFO] FASE 3: Verificando persistencia del volumen..."
WAIT_TIMEOUT=60; ELAPSED=0; while [ ! -d "$CACHE_DIR" ]; do if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció."; exit 1; fi; echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2)); done;
echo " ¡Volumen persistente verificado!"

echo "[INFO] FASE 4: Creando enlaces e instalando dependencias de nodos..."
mkdir -p "${WORKFLOWS_DEST_DIR}"; cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"; cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"

# --- [INICIO DEL CÓDIGO CORREGIDO] ---
# Se utiliza una tubería (`|`) en lugar de la sustitución de procesos (`< <(...)`)
# para asegurar la compatibilidad con el intérprete /bin/sh.
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++' | while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs); SOURCE_PATH="${CACHE_DIR}/${name}"
    case "$type" in
        GIT)
            DEST_PATH="${CUSTOM_NODES_DIR}/${name}"; 
            if [ -d "$SOURCE_PATH" ]; then 
                ln -sf "$SOURCE_PATH" "$DEST_PATH"; 
                REQ_FILE="${DEST_PATH}/requirements.txt"; 
                if [ -f "$REQ_FILE" ]; then 
                    pip install -r "$REQ_FILE"; 
                fi; 
            fi;;
        URL_AUTH)
            DEST_PATH="${MODELS_DIR}/${name}"; 
            if [ -d "$SOURCE_PATH" ]; then 
                mkdir -p "$DEST_PATH"; 
                ln -sf "$SOURCE_PATH"/* "$DEST_PATH/"; 
            elif [ -f "$SOURCE_PATH" ]; then 
                mkdir -p "$(dirname "$DEST_PATH")"; 
                ln -sf "$SOURCE_PATH" "$DEST_PATH"; 
            fi;;
    esac
done
# --- [FIN DEL CÓDIGO CORREGIDO] ---


# --- FASE 4.5: ARMONIZACIÓN NO DESTRUCTIVA ---
echo "[INFO] FASE 4.5: Iniciando armonización NO DESTRUCTIVA..."
pip install --no-cache-dir onnxruntime==1.17.1 onnxruntime-gpu==1.17.1 "numpy<2"

# --- DIAGNÓSTICO FINAL Y ARRANQUE ---
echo "[DIAGNOSIS] ESTADO FINAL DE DEPENDENCIAS:"
pip list | grep -E "onnx|insightface|numpy"
echo "[DIAGNOSIS] Resultado de 'pip check':"
pip check || true

echo "[INFO] FASE 5: Iniciando servicios..."
COMFYUI_LOG_FILE="${NETWORK_VOLUME_PATH}/comfyui_log_${UNIQUE_ID}.txt"
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 --verbose > "${COMFYUI_LOG_FILE}" 2>&1 &
TIMEOUT=180; ELAPSED=0; while true; do if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then echo " ComfyUI está listo!"; break; else echo -n "."; fi; if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió."; exit 1; fi; sleep 3; ELAPSED=$((ELAPSED + 3)); done

echo "[INFO] FASE 6: Iniciando handler..."
cd "${CONFIG_SOURCE_DIR}"; exec python3 -u morpheus_handler.py

# Si el script llega aquí, es que algo ha ido mal antes de exec
echo "[FATAL] El script ha finalizado inesperadamente antes de lanzar el handler."
exit 1
