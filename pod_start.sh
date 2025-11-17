#!/bin/bash

# ==============================================================================
# Script de Arranque v37.2 (Fontanería Reforzada)
# ==============================================================================

# set -e # Descomentar para debug si algo falla
set -o pipefail

# --- FASE 0: PREPARACIÓN DE LOGS ÚNICOS ---
NETWORK_VOLUME_PATH="/runpod-volume"
UNIQUE_ID=$(date +%Y%m%d_%H%M%S_%N)
MASTER_LOG_FILE="${NETWORK_VOLUME_PATH}/log_${UNIQUE_ID}.txt"

exec > >(tee -a "${MASTER_LOG_FILE}") 2>&1

echo "--- INICIO DEL LOG DE ARRANQUE (ID: ${UNIQUE_ID}) ---"
echo "====================================================================="


# --- FASE 1: DEPENDENCIAS DEL SISTEMA ---
echo "[INFO] FASE 1: Instalando dependencias del sistema..."
apt-get update && apt-get install -y build-essential python3-dev curl unzip git
pip install --upgrade pip

# --- FASE 1.5: CONSTRUCCIÓN DEL ENTORNO BASE MODERNO ---
echo "[INFO] FASE 1.5: Construyendo el entorno Python base con versiones modernas y compatibles..."
pip install --no-cache-dir "numpy>=2.0" "onnxruntime-gpu>=1.18" opencv-python-headless insightface==0.7.3 facexlib timm ftfy

# --- FASES 2 Y 3: DEFINICIÓN DE RUTAS Y VERIFICACIÓN ---
echo "[INFO] FASE 2: Definiendo rutas..."
CONFIG_SOURCE_DIR="/workspace/morpheus_config" 
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"

echo "[INFO] FASE 3: Verificando persistencia del volumen..."
WAIT_TIMEOUT=60; ELAPSED=0; while [ ! -d "$CACHE_DIR" ]; do if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció."; exit 1; fi; echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2)); done;
echo " ¡Volumen persistente verificado!"


# --- FASE 4: PREPARACIÓN FÍSICA ANTES DEL ARRANQUE ---
echo "[INFO] FASE 4: Creando enlaces desde el almacenamiento persistente..."
mkdir -p "${CUSTOM_NODES_DIR}"
mkdir -p "${WORKFLOWS_DEST_DIR}"

cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"; cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"

# --- [INICIO DE LA CORRECCIÓN DE FONTANERÍA] ---
# Se crean explícitamente los enlaces a las carpetas de modelos críticos.
echo "[ACCIÓN] Creando enlaces explícitos para modelos críticos..."
IPADAPTER_SOURCE_DIR="${CACHE_DIR}/ipadapter"
IPADAPTER_DEST_DIR="${MODELS_DIR}/ipadapter"
if [ -d "$IPADAPTER_SOURCE_DIR" ]; then
    mkdir -p "$IPADAPTER_DEST_DIR"
    ln -sf "$IPADAPTER_SOURCE_DIR"/* "$IPADAPTER_DEST_DIR/"
    echo "Enlace para modelos IPAdapter creado."
else
    echo "[AVISO] Directorio de origen para IPAdapter no encontrado: $IPADAPTER_SOURCE_DIR"
fi
CONTROLNET_SOURCE_DIR="${CACHE_DIR}/controlnet"
CONTROLNET_DEST_DIR="${MODELS_DIR}/controlnet"
if [ -d "$CONTROLNET_SOURCE_DIR" ]; then
    mkdir -p "$CONTROLNET_DEST_DIR"
    ln -sf "$CONTROLNET_SOURCE_DIR"/* "$CONTROLNET_DEST_DIR/"
    echo "Enlace para modelos ControlNet creado."
else
    echo "[AVISO] Directorio de origen para ControlNet no encontrado: $CONTROLNET_SOURCE_DIR"
fi
# --- [FIN DE LA CORRECCIÓN DE FONTANERÍA] ---

RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++' | while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs)
    SOURCE_PATH="${CACHE_DIR}/${name}"
    
    case "$type" in
        GIT)
            DEST_PATH="${CUSTOM_NODES_DIR}/${name}"; 
            if [ -d "$SOURCE_PATH" ]; then
                echo "Enlazando nodo desde '$SOURCE_PATH' a '$DEST_PATH'..."
                ln -sf "$SOURCE_PATH" "$DEST_PATH"; 
                REQ_FILE="${DEST_PATH}/requirements.txt"; 
                if [ -f "$REQ_FILE" ]; then 
                    echo "Instalando requirements para '$name' (modo defensivo)..."
                    pip install --upgrade-strategy "only-if-needed" -r "$REQ_FILE"; 
                fi; 
            else
                echo "[AVISO] El directorio de origen '$SOURCE_PATH' para el nodo '$name' no existe. Saltando enlace."
            fi;;
        URL_AUTH)
            DEST_PATH="${MODELS_DIR}/${name}"; 
            if [ -e "$SOURCE_PATH" ]; then
                echo "Enlazando modelo desde '$SOURCE_PATH' a '$DEST_PATH'..."
                mkdir -p "$(dirname "$DEST_PATH")"
                ln -sf "$SOURCE_PATH" "$DEST_PATH"; 
            else
                 echo "[AVISO] El archivo/directorio de origen '$SOURCE_PATH' para el modelo '$name' no existe. Saltando enlace."
            fi;;
    esac
done

# --- DIAGNÓSTICO PRE-ARRANQUE ---
echo "[DIAGNOSIS] Contenido final de custom_nodes ANTES de arrancar ComfyUI:"
ls -l "${CUSTOM_NODES_DIR}"
echo "[DIAGNOSIS] Resultado de 'pip check' ANTES de arrancar ComfyUI:"
pip check || true


# --- FASE 5: ARRANQUE DE SERVICIOS (AHORA AL FINAL) ---
echo "[INFO] FASE 5: Todo preparado. Iniciando servicios..."
COMFYUI_LOG_FILE="${NETWORK_VOLUME_PATH}/comfyui_log_${UNIQUE_ID}.txt"
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 --verbose > "${COMFYUI_LOG_FILE}" 2>&1 &
TIMEOUT=180; ELAPSED=0; while true; do if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then echo " ComfyUI está listo!"; break; else echo -n "."; fi; if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió."; cat "${COMFYUI_LOG_FILE}"; exit 1; fi; sleep 3; ELAPSED=$((ELAPSED + 3)); done

# --- FASE 6: INICIO DEL HANDLER ---
echo "[INFO] FASE 6: Iniciando handler..."
cd "${CONFIG_SOURCE_DIR}"; exec python3 -u morpheus_handler.py

# Si el script llega aquí, es que algo ha ido mal antes de exec
echo "[FATAL] El script ha finalizado inesperadamente antes de lanzar el handler."
exit 1
