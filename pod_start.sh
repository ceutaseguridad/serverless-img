#!/bin/bash

# ==============================================================================
# Script de Arranque v29 (Instalación de Dependencias Robusta y Final)
# VERSIÓN DE DIAGNÓSTICO TOTAL
# ==============================================================================

set -e
set -o pipefail

# --- FASE 0: PREPARACIÓN DEL LOG MAESTRO ---
# Todas las salidas de este script se guardarán aquí.
NETWORK_VOLUME_PATH="/runpod-volume"
MASTER_LOG_FILE="${NETWORK_VOLUME_PATH}/master_diagnostic_log.txt"

# Sobrescribe el log anterior para una ejecución limpia.
echo "--- INICIO DEL LOG DE DIAGNÓSTICO MAESTRO ---" > "${MASTER_LOG_FILE}"
echo "Fecha y Hora de Inicio: $(date)" >> "${MASTER_LOG_FILE}"
echo "=====================================================================" >> "${MASTER_LOG_FILE}"


# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS DEL SISTEMA Y BASE DE PYTHON ---
echo "[INFO] FASE 1: Iniciando..." >> "${MASTER_LOG_FILE}"
echo "[ACTION] Ejecutando: apt-get update && apt-get install..." >> "${MASTER_LOG_FILE}"
apt-get update >> "${MASTER_LOG_FILE}" 2>&1 && apt-get install -y build-essential python3-dev curl unzip git >> "${MASTER_LOG_FILE}" 2>&1
echo "[SUCCESS] Dependencias del sistema instaladas." >> "${MASTER_LOG_FILE}"

echo "[ACTION] Ejecutando: pip install --upgrade pip" >> "${MASTER_LOG_FILE}"
pip install --upgrade pip >> "${MASTER_LOG_FILE}" 2>&1
echo "[SUCCESS] Pip actualizado." >> "${MASTER_LOG_FILE}"

echo "[ACTION] Forzando instalación de dependencias base de Python..." >> "${MASTER_LOG_FILE}"
pip install --upgrade --no-cache-dir --force-reinstall insightface==0.7.3 facexlib timm ftfy requests xformers "huggingface-hub<1.0" >> "${MASTER_LOG_FILE}" 2>&1
echo "[SUCCESS] Dependencias base de Python instaladas." >> "${MASTER_LOG_FILE}"

echo "--- [DIAGNOSIS] ESTADO DE DEPENDENCIAS 'ANTES' DE NODOS ---" >> "${MASTER_LOG_FILE}"
echo "-> Versión de Python:" >> "${MASTER_LOG_FILE}"
python3 --version >> "${MASTER_LOG_FILE}" 2>&1
echo "-> Versión de Pip:" >> "${MASTER_LOG_FILE}"
pip --version >> "${MASTER_LOG_FILE}" 2>&1
echo "-> Paquetes clave instalados:" >> "${MASTER_LOG_FILE}"
pip list | grep -E "onnx|insightface|torch|xformers|facexlib" >> "${MASTER_LOG_FILE}"
echo "=====================================================================" >> "${MASTER_LOG_FILE}"


# --- FASE 2: DEFINICIÓN Y VERIFICACIÓN DE RUTAS ---
echo "[INFO] FASE 2: Definiendo rutas..." >> "${MASTER_LOG_FILE}"
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 
NETWORK_VOLUME_PATH="/runpod-volume"
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
echo "[SUCCESS] Rutas definidas." >> "${MASTER_LOG_FILE}"

echo "--- [DEBUG] Verificación de variables de ruta ---" >> "${MASTER_LOG_FILE}"
echo "CONFIG_SOURCE_DIR=${CONFIG_SOURCE_DIR}" >> "${MASTER_LOG_FILE}"
echo "NETWORK_VOLUME_PATH=${NETWORK_VOLUME_PATH}" >> "${MASTER_LOG_FILE}"
echo "CACHE_DIR=${CACHE_DIR}" >> "${MASTER_LOG_FILE}"
echo "WORKFLOWS_DEST_DIR=${WORKFLOWS_DEST_DIR}" >> "${MASTER_LOG_FILE}"
echo "COMFYUI_DIR=${COMFYUI_DIR}" >> "${MASTER_LOG_FILE}"
echo "CUSTOM_NODES_DIR=${CUSTOM_NODES_DIR}" >> "${MASTER_LOG_FILE}"
echo "MODELS_DIR=${MODELS_DIR}" >> "${MASTER_LOG_FILE}"
echo "=====================================================================" >> "${MASTER_LOG_FILE}"


# --- FASE 3: VERIFICACIÓN DEL VOLUMEN ---
echo "[INFO] FASE 3: Verificando persistencia del volumen en ${CACHE_DIR}..." >> "${MASTER_LOG_FILE}"
WAIT_TIMEOUT=60; ELAPSED=0; while [ ! -d "$CACHE_DIR" ]; do if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció."; exit 1; fi; echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2)); done;
echo "[SUCCESS] ¡Volumen persistente verificado!" >> "${MASTER_LOG_FILE}"
echo "=====================================================================" >> "${MASTER_LOG_FILE}"


# --- FASE 4: PREPARACIÓN DEL ENTORNO, ENLACES E INSTALACIÓN DE DEPENDENCIAS DE NODOS ---
echo "[INFO] FASE 4: Iniciando..." >> "${MASTER_LOG_FILE}"
echo "[ACTION] Creando directorios y copiando workflows..." >> "${MASTER_LOG_FILE}"
mkdir -p "${WORKFLOWS_DEST_DIR}" >> "${MASTER_LOG_FILE}" 2>&1
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/" >> "${MASTER_LOG_FILE}" 2>&1
cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py" >> "${MASTER_LOG_FILE}" 2>&1
echo "[SUCCESS] Tareas de preparación completadas." >> "${MASTER_LOG_FILE}"

RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
echo "[INFO] Procesando el fichero de recursos: ${RESOURCE_FILE}" >> "${MASTER_LOG_FILE}"

while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs)
    SOURCE_PATH="${CACHE_DIR}/${name}"
    
    echo "--- [LOOP] Procesando: Type='${type}', Name='${name}' ---" >> "${MASTER_LOG_FILE}"
    
    case "$type" in
        GIT)
            DEST_PATH="${CUSTOM_NODES_DIR}/${name}"
            echo "[DEBUG] GIT Type. Origen: ${SOURCE_PATH}, Destino: ${DEST_PATH}" >> "${MASTER_LOG_FILE}"
            if [ -d "$SOURCE_PATH" ]; then
                echo "[ACTION] Creando enlace simbólico para ${name}..." >> "${MASTER_LOG_FILE}"
                ln -sf "$SOURCE_PATH" "$DEST_PATH"
                echo "[DEBUG] Verificando enlace..." >> "${MASTER_LOG_FILE}"
                ls -ld "${DEST_PATH}" >> "${MASTER_LOG_FILE}" 2>&1
                
                REQ_FILE="${DEST_PATH}/requirements.txt"
                if [ -f "$REQ_FILE" ]; then
                    echo "[INFO] Fichero requirements.txt encontrado en ${REQ_FILE}" >> "${MASTER_LOG_FILE}"
                    echo "--- [DEBUG] Contenido de ${REQ_FILE} ---" >> "${MASTER_LOG_FILE}"
                    cat "${REQ_FILE}" >> "${MASTER_LOG_FILE}"
                    echo "--- Fin del contenido ---" >> "${MASTER_LOG_FILE}"
                    echo "[ACTION] Instalando dependencias desde ${REQ_FILE}..." >> "${MASTER_LOG_FILE}"
                    pip install -r "$REQ_FILE" >> "${MASTER_LOG_FILE}" 2>&1
                    echo "[SUCCESS] Dependencias para '${name}' instaladas." >> "${MASTER_LOG_FILE}"
                else
                    echo "[INFO] No se encontró requirements.txt para '${name}'." >> "${MASTER_LOG_FILE}"
                fi
            else
                 echo "[WARNING] El directorio de origen GIT no existe: ${SOURCE_PATH}" >> "${MASTER_LOG_FILE}"
            fi
            ;;
        URL_AUTH)
            DEST_PATH="${MODELS_DIR}/${name}"
            echo "[DEBUG] URL_AUTH Type. Origen: ${SOURCE_PATH}, Destino: ${DEST_PATH}" >> "${MASTER_LOG_FILE}"
            if [ -d "$SOURCE_PATH" ]; then
                mkdir -p "$DEST_PATH"
                ln -sf "$SOURCE_PATH"/* "$DEST_PATH/"
                echo "[SUCCESS] Enlace de Directorio URL_AUTH Creado: ${SOURCE_PATH}/* -> ${DEST_PATH}/" >> "${MASTER_LOG_FILE}"
            elif [ -f "$SOURCE_PATH" ]; then
                mkdir -p "$(dirname "$DEST_PATH")"
                ln -sf "$SOURCE_PATH" "$DEST_PATH"
                echo "[SUCCESS] Enlace de Archivo URL_AUTH Creado: ${SOURCE_PATH} -> ${DEST_PATH}" >> "${MASTER_LOG_FILE}"
            else
                echo "[WARNING] El origen URL_AUTH no existe: ${SOURCE_PATH}" >> "${MASTER_LOG_FILE}"
            fi
            ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++')

echo "[SUCCESS] Creación de enlaces y dependencias de nodos finalizada." >> "${MASTER_LOG_FILE}"

echo "--- [DIAGNOSIS] ESTADO DE DEPENDENCIAS 'DESPUÉS' DE NODOS ---" >> "${MASTER_LOG_FILE}"
echo "-> Paquetes clave instalados:" >> "${MASTER_LOG_FILE}"
pip list | grep -E "onnx|insightface|torch|xformers|facexlib|onnxruntime" >> "${MASTER_LOG_FILE}"
echo "--- [DIAGNOSIS] Verificación de consistencia con 'pip check' ---" >> "${MASTER_LOG_FILE}"
pip check >> "${MASTER_LOG_FILE}" 2>&1 || true
echo "=====================================================================" >> "${MASTER_LOG_FILE}"


# --- FASE 4.5: APLICACIÓN DE PARCHES EN CALIENTE ---
echo "[INFO] FASE 4.5: Iniciando..." >> "${MASTER_LOG_FILE}"
PULID_PY_PATH="${CACHE_DIR}/ComfyUI-PuLID/pulid.py"
echo "[ACTION] Intentando aplicar parche a ${PULID_PY_PATH}..." >> "${MASTER_LOG_FILE}"
if [ -f "$PULID_PY_PATH" ]; then
    sed -i 's/name="antelopev2"/name="buffalo_l"/' "$PULID_PY_PATH"
    echo "[SUCCESS] Parche para PuLID aplicado." >> "${MASTER_LOG_FILE}"
else
    echo "[WARNING] No se encontró 'pulid.py'. Se omite el parche." >> "${MASTER_LOG_FILE}"
fi
echo "=====================================================================" >> "${MASTER_LOG_FILE}"


# --- FASE 5: INICIO DE SERVICIOS ---
echo "[INFO] FASE 5: Iniciando servicios..." >> "${MASTER_LOG_FILE}"
COMFYUI_LOG_FILE="${NETWORK_VOLUME_PATH}/comfyui_startup.log"
echo "[INFO] Iniciando ComfyUI. Su log de arranque se guardará por separado en ${COMFYUI_LOG_FILE}" >> "${MASTER_LOG_FILE}"
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 --verbose > "${COMFYUI_LOG_FILE}" 2>&1 &
echo "[INFO]    -> Comando de inicio de ComfyUI enviado a segundo plano." >> "${MASTER_LOG_FILE}"

TIMEOUT=180; ELAPSED=0; while true; do if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then echo; echo "[SUCCESS] ¡Servidor de ComfyUI está listo!"; break; else echo -n "."; fi; if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió en ${TIMEOUT} segundos."; echo "¡ERROR FATAL! ComfyUI no respondió en ${TIMEOUT} segundos." >> "${MASTER_LOG_FILE}"; exit 1; fi; sleep 3; ELAPSED=$((ELAPSED + 3)); done
echo "=====================================================================";
