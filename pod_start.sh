#!/bin/bash

# ==============================================================================
# Script de Arranque v32 (Solución Final con Armonización Total de Dependencias)
# ==============================================================================

set -e
set -o pipefail

# --- FASE 0: PREPARACIÓN DEL LOG ---
NETWORK_VOLUME_PATH="/runpod-volume"
MASTER_LOG_FILE="${NETWORK_VOLUME_PATH}/final_solution_log.txt"
echo "--- INICIO DEL LOG DE LA SOLUCIÓN FINAL v32 ---" > "${MASTER_LOG_FILE}"
echo "Fecha y Hora de Inicio: $(date)" >> "${MASTER_LOG_FILE}"
echo "=====================================================================" >> "${MASTER_LOG_FILE}"


# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS DEL SISTEMA Y BASE (NO DESTRUCTIVA) ---
echo "[INFO] FASE 1: Instalando dependencias del sistema y actualizando pip..." >> "${MASTER_LOG_FILE}"
apt-get update > /dev/null 2>&1 && apt-get install -y build-essential python3-dev curl unzip git > /dev/null 2>&1
pip install --upgrade pip >> "${MASTER_LOG_FILE}" 2>&1

# Enfoque minimalista: NO usamos --force-reinstall. Respetamos la plantilla de RunPod.
echo "[INFO] Instalando dependencias adicionales (insightface, facexlib, etc.)..." >> "${MASTER_LOG_FILE}"
pip install --no-cache-dir insightface==0.7.3 facexlib timm ftfy >> "${MASTER_LOG_FILE}" 2>&1
echo "[SUCCESS] Dependencias adicionales instaladas." >> "${MASTER_LOG_FILE}"

# --- DIAGNÓSTICO POST-INSTALACIÓN ---
echo "--- [DIAGNOSIS] ESTADO DE DEPENDENCIAS 'ANTES' DE NODOS ---" >> "${MASTER_LOG_FILE}"
pip list | grep -E "onnx|insightface|torch|xformers|onnxruntime|numpy" >> "${MASTER_LOG_FILE}"
echo "=====================================================================" >> "${MASTER_LOG_FILE}"


# --- FASE 2: DEFINICIÓN DE RUTAS ---
echo "[INFO] FASE 2: Definiendo rutas..." >> "${MASTER_LOG_FILE}"
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 
NETWORK_VOLUME_PATH="/runpod-volume"
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
echo "[SUCCESS] Rutas definidas." >> "${MASTER_LOG_FILE}"


# --- FASE 3: VERIFICACIÓN DEL VOLUMEN ---
echo "[INFO] FASE 3: Verificando persistencia del volumen en ${CACHE_DIR}..." >> "${MASTER_LOG_FILE}"
WAIT_TIMEOUT=60; ELAPSED=0; while [ ! -d "$CACHE_DIR" ]; do if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció." >> "${MASTER_LOG_FILE}"; exit 1; fi; echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2)); done;
echo "[SUCCESS] ¡Volumen persistente verificado!" >> "${MASTER_LOG_FILE}"


# --- FASE 4: PREPARACIÓN DEL ENTORNO E INSTALACIÓN DE DEPENDENCIAS DE NODOS ---
echo "[INFO] FASE 4: Creando enlaces e instalando dependencias de nodos..." >> "${MASTER_LOG_FILE}"
mkdir -p "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/" >> "${MASTER_LOG_FILE}" 2>&1
cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py" >> "${MASTER_LOG_FILE}" 2>&1
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
                echo "[INFO]    -> Enlace GIT Creado: ${SOURCE_PATH} -> ${DEST_PATH}" >> "${MASTER_LOG_FILE}"
                
                REQ_FILE="${DEST_PATH}/requirements.txt"
                if [ -f "$REQ_FILE" ]; then
                    echo "[INFO]    -> Encontrado requirements.txt para '${name}'. Instalando..." >> "${MASTER_LOG_FILE}"
                    pip install -r "$REQ_FILE" >> "${MASTER_LOG_FILE}" 2>&1
                    echo "[SUCCESS]    -> Dependencias para '${name}' instaladas." >> "${MASTER_LOG_FILE}"
                fi
            fi
            ;;
        URL_AUTH)
            DEST_PATH="${MODELS_DIR}/${name}"
            if [ -d "$SOURCE_PATH" ]; then
                mkdir -p "$DEST_PATH"; ln -sf "$SOURCE_PATH"/* "$DEST_PATH/";
            elif [ -f "$SOURCE_PATH" ]; then
                mkdir -p "$(dirname "$DEST_PATH")"; ln -sf "$SOURCE_PATH" "$DEST_PATH";
            fi
            ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++')

echo "[SUCCESS] Creación de enlaces y dependencias de nodos finalizada." >> "${MASTER_LOG_FILE}"


# --- FASE 4.5: ARMONIZACIÓN TOTAL DE DEPENDENCIAS (LA SOLUCIÓN FINAL) ---
echo "[INFO] FASE 4.5: Iniciando armonización total de dependencias..." >> "${MASTER_LOG_FILE}"
echo "[ACTION] Forzando la instalación de versiones consistentes de onnxruntime, onnxruntime-gpu y numpy..." >> "${MASTER_LOG_FILE}"
# Esto desinstalará las versiones conflictivas y las reemplazará por versiones compatibles.
pip install --no-cache-dir --force-reinstall onnxruntime==1.17.1 onnxruntime-gpu==1.17.1 numpy==2.2.0 >> "${MASTER_LOG_FILE}" 2>&1
echo "[SUCCESS] Armonización completada. El entorno ahora debería ser totalmente consistente." >> "${MASTER_LOG_FILE}"


# --- DIAGNÓSTICO FINAL DE DEPENDENCIAS ---
echo "--- [DIAGNOSIS] ESTADO FINAL DE DEPENDENCIAS (POST-ARMONIZACIÓN) ---" >> "${MASTER_LOG_FILE}"
pip list | grep -E "onnx|insightface|torch|xformers|onnxruntime|numpy" >> "${MASTER_LOG_FILE}"
echo "--- [DIAGNOSIS] Verificación de consistencia final con 'pip check' ---" >> "${MASTER_LOG_FILE}"
pip check >> "${MASTER_LOG_FILE}" 2>&1 || true
echo "=====================================================================" >> "${MASTER_LOG_FILE}"


# --- FASE 4.6: APLICACIÓN DE PARCHES EN CALIENTE ---
echo "[INFO] FASE 4.6: Aplicando parche de retrocompatibilidad para PuLID..." >> "${MASTER_LOG_FILE}"
PULID_PY_PATH="${CACHE_DIR}/ComfyUI-PuLID/pulid.py"
if [ -f "$PULID_PY_PATH" ]; then
    sed -i 's/name="antelopev2"/name="buffalo_l"/' "$PULID_PY_PATH"
    echo "[SUCCESS]    -> Parche para PuLID aplicado." >> "${MASTER_LOG_FILE}"
else
    echo "[WARNING]    -> No se encontró 'pulid.py'. Se omite el parche." >> "${MASTER_LOG_FILE}"
fi


# --- FASE 5: INICIO DE SERVICIOS ---
echo "[INFO] FASE 5: Iniciando servicios..." >> "${MASTER_LOG_FILE}"
COMFYUI_LOG_FILE="${NETWORK_VOLUME_PATH}/comfyui_startup.log"
echo "[INFO] Iniciando ComfyUI. Su log se guardará en ${COMFYUI_LOG_FILE}" >> "${MASTER_LOG_FILE}"
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 --verbose > "${COMFYUI_LOG_FILE}" 2>&1 &
echo "[INFO]    -> Servidor de ComfyUI iniciado en segundo plano." >> "${MASTER_LOG_FILE}"

TIMEOUT=180; ELAPSED=0; while true; do if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then echo; echo "[SUCCESS] ¡Servidor de ComfyUI está listo!"; echo "[SUCCESS] ¡Servidor de ComfyUI está listo!" >> "${MASTER_LOG_FILE}"; break; else echo -n "."; fi; if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió en ${TIMEOUT} segundos."; echo "¡ERROR FATAL! ComfyUI no respondió en ${TIMEOUT} segundos." >> "${MASTER_LOG_FILE}"; exit 1; fi; sleep 3; ELAPSED=$((ELAPSED + 3)); done
echo "====================================================================="; echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"; echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---" >> "${MASTER_LOG_FILE}"

# --- FASE 6: INICIO DEL HANDLER DE MORPHEUS ---
cd "${CONFIG_SOURCE_DIR}"; echo "[INFO] Iniciando el handler 'morpheus_handler.py'..."; echo "[INFO] Iniciando el handler 'morpheus_handler.py'..." >> "${MASTER_LOG_FILE}"; exec python3 -u morpheus_handler.py
