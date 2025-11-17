#!/bin-bash

# ==============================================================================
# Script de Arranque v29 (Instalación de Dependencias Robusta y Final)
# VERSIÓN DE DIAGNÓSTICO - MODIFICACIÓN MÍNIMA
# ==============================================================================

set -e
set -o pipefail

# --- [MODIFICACIÓN 1: INICIO] DEFINIR FICHERO DE LOG ---
NETWORK_VOLUME_PATH="/runpod-volume"
LOG_FILE="${NETWORK_VOLUME_PATH}/diagnostic_v29_log.txt"
echo "--- INICIO DEL LOG DE DIAGNÓSTICO v29 ---" > "${LOG_FILE}"
echo "Fecha y Hora: $(date)" >> "${LOG_FILE}"
echo "=======================================" >> "${LOG_FILE}"
# --- [MODIFICACIÓN 1: FIN] ---


# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias..."
apt-get update > /dev/null 2>&1 && apt-get install -y build-essential python3-dev curl unzip git > /dev/null 2>&1
pip install --upgrade pip
echo "[MORPHEUS-STARTUP]    -> Forzando instalación de dependencias base..."
# --- [MODIFICACIÓN 2: INICIO] REDIRIGIR SALIDA DE PIP AL LOG ---
pip install --upgrade --no-cache-dir --force-reinstall insightface==0.7.3 facexlib timm ftfy requests xformers "huggingface-hub<1.0" >> "${LOG_FILE}" 2>&1
# --- [MODIFICACIÓN 2: FIN] ---
echo "[MORPHEUS-STARTUP]    -> Dependencias base instaladas."

# --- [MODIFICACIÓN 3: INICIO] LOG DEL ESTADO "ANTES" ---
echo "--- ESTADO DE DEPENDENCIAS 'ANTES' ---" >> "${LOG_FILE}"
pip list | grep -E "onnx|insightface|onnxruntime" >> "${LOG_FILE}"
echo "=======================================" >> "${LOG_FILE}"
# --- [MODIFICACIÓN 3: FIN] ---


echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v29 ---"
echo "====================================================================="

# --- FASE 2: DEFINICIÓN DE RUTAS ---
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 
NETWORK_VOLUME_PATH="/runpod-volume"
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
echo "[MORPHEUS-STARTUP] FASE 2: Rutas definidas."

# --- FASE 3: VERIFICACIÓN DEL VOLUMEN ---
echo "[MORPHEUS-STARTUP] FASE 3: Esperando volumen persistente..."
WAIT_TIMEOUT=60; ELAPSED=0; while [ ! -d "$CACHE_DIR" ]; do if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció."; exit 1; fi; echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2)); done; echo " ¡Volumen persistente verificado!"

# --- FASE 4: PREPARACIÓN DEL ENTORNO, ENLACES E INSTALACIÓN DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] FASE 4: Creando enlaces e instalando dependencias de nodos..."
mkdir -p "${WORKFLOWS_DEST_DIR}"; cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"; cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"

while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs)
    SOURCE_PATH="${CACHE_DIR}/${name}"
    
    case "$type" in
        GIT)
            DEST_PATH="${CUSTOM_NODES_DIR}/${name}"
            if [ -d "$SOURCE_PATH" ]; then
                ln -sf "$SOURCE_PATH" "$DEST_PATH"
                echo "[MORPHEUS-STARTUP]    -> Enlace GIT Creado: ${SOURCE_PATH} -> ${DEST_PATH}"
                
                # --- [INICIO DE LA CORRECCIÓN LÓGICA] ---
                # Inmediatamente después de crear el enlace, buscamos e instalamos sus dependencias.
                REQ_FILE="${DEST_PATH}/requirements.txt"
                if [ -f "$REQ_FILE" ]; then
                    echo "[MORPHEUS-STARTUP]    -> Encontrado requirements.txt para '${name}'. Instalando..."
                    # --- [MODIFICACIÓN 4: INICIO] REDIRIGIR SALIDA DE PIP AL LOG ---
                    pip install -r "$REQ_FILE" >> "${LOG_FILE}" 2>&1
                    # --- [MODIFICACIÓN 4: FIN] ---
                    echo "[MORPHEUS-STARTUP]    -> Dependencias para '${name}' instaladas."
                fi
                # --- [FIN DE LA CORRECCIÓN LÓGICA] ---
            fi
            ;;
        URL_AUTH)
            # (Esta parte se mantiene igual que la v28)
            DEST_PATH="${MODELS_DIR}/${name}"
            if [ -d "$SOURCE_PATH" ]; then
                mkdir -p "$DEST_PATH"; ln -sf "$SOURCE_PATH"/* "$DEST_PATH/"; echo "[MORPHEUS-STARTUP]    -> Enlace Directorio URL_AUTH Creado: ${SOURCE_PATH}/* -> ${DEST_PATH}/"
            elif [ -f "$SOURCE_PATH" ]; then
                mkdir -p "$(dirname "$DEST_PATH")"; ln -sf "$SOURCE_PATH" "$DEST_PATH"; echo "[MORPHEUS-STARTUP]    -> Enlace Archivo URL_AUTH Creado: ${SOURCE_PATH} -> ${DEST_PATH}"
            fi
            ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++')

echo "[MORPHEUS-STARTUP]    -> Creación de enlaces y dependencias finalizada."

# --- [MODIFICACIÓN 5: INICIO] LOG DEL ESTADO "DESPUÉS" Y PIP CHECK ---
echo "--- ESTADO DE DEPENDENCIAS 'DESPUÉS' ---" >> "${LOG_FILE}"
pip list | grep -E "onnx|insightface|onnxruntime" >> "${LOG_FILE}"
echo "=======================================" >> "${LOG_FILE}"
echo "--- RESULTADO DE 'pip check' ---" >> "${LOG_FILE}"
pip check >> "${LOG_FILE}" 2>&1 || true
echo "=======================================" >> "${LOG_FILE}"
# --- [MODIFICACIÓN 5: FIN] ---


# ==============================================================================
# FASE 4.5: APLICACIÓN DE PARCHES EN CALIENTE (MANTENIDO)
# ==============================================================================
PULID_PY_PATH="${CACHE_DIR}/ComfyUI-PuLID/pulid.py"
echo "[MORPHEUS-STARTUP] FASE 4.5: Aplicando parche de retrocompatibilidad para PuLID..."
if [ -f "$PULID_PY_PATH" ]; then
    sed -i 's/name="antelopev2"/name="buffalo_l"/' "$PULID_PY_PATH"; echo "[MORPHEUS-STARTUP]    -> Parche para PuLID aplicado."
else
    echo "[MORPHEUS-STARTUP]    -> ADVERTENCIA: No se encontró 'pulid.py'. Se omite el parche."
fi
# ==============================================================================

# --- FASE 5: INICIO DE SERVICIOS ---
echo "[MORPHEUS-STARTUP] FASE 5: Iniciando servicios..."
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 --verbose &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado."
TIMEOUT=180; ELAPSED=0; while true; do if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then echo; echo "[MORPHEUS-STARTUP] -> ¡Servidor de ComfyUI está listo!"; break; else echo -n "."; fi; if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió."; exit 1; fi; sleep 3; ELAPSED=$((ELAPSED + 3)); done
echo "====================================================================="; echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"; echo "====================================================================="

# --- FASE 6: INICIO DEL HANDLER DE MORPHEUS ---
cd "${CONFIG_SOURCE_DIR}"; echo "[MORPHEUS-STARTUP] Iniciando el handler 'morpheus_handler.py'..."; exec python3 -u morpheus_handler.py
