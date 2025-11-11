#!/bin/bash

# ==============================================================================
# Script de Arranque v12 (Infalible) para Morpheus AI Suite
# Instala todas las dependencias, utiliza un caché pre-poblado y
# soluciona la importación del handler de forma definitiva.
# =================================.=============================================

set -e
set -o pipefail

# --- FASE 1: INSTALACIÓN COMPLETA DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias..."

apt-get update && apt-get install -y curl
echo "[MORPHEUS-STARTUP]    -> Dependencias de sistema (curl) instaladas."

# [CORRECCIÓN] Añadimos 'timm' a la lista de dependencias de Python.
pip install insightface onnxruntime-gpu facexlib timm
echo "[MORPHEUS-STARTUP]    -> Dependencias de Python completas instaladas."


echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v12 (INFALIBLE)    ---"
echo "====================================================================="

# --- FASE 2: CONFIGURACIÓN DE RUTAS Y ENTORNO ---
COMFYUI_DIR="/comfyui"
CONFIG_SOURCE_DIR="/workspace/morpheus_config"
# [CORRECCIÓN DEFINITIVA] Copiamos el handler original al mismo directorio que el nuestro.
# Esto elimina cualquier problema de PYTHONPATH o de directorios de trabajo.
cp /comfy_handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"
echo "[MORPHEUS-STARTUP]    -> Handler original copiado para asegurar la importación."

# ... (el resto de la configuración de rutas es igual) ...
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
    # ... (bucle sin cambios)
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
TIMEOUT=120; ELAPSED=0
while true; do
    if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then
        echo "[MORPHEUS-STARTUP]    -> ¡Servidor de ComfyUI está listo!"; break
    else
        echo -n "." # Imprime un punto para mostrar que sigue esperando
    fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió."; exit 1; fi
    sleep 3; ELAPSED=$((ELAPSED + 3))
done

echo
echo "====================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"
echo "====================================================================="

# --- FASE 5: INICIO DEL HANDLER PERSONALIZADO ---
echo "[MORPHEUS-STARTUP] Iniciando el handler personalizado de Morpheus..."
# Ahora ejecutamos desde el directorio del código clonado.
cd "${CONFIG_SOURCE_DIR}"
exec python3 -u morpheus_handler.py
wait -n
exit $?
