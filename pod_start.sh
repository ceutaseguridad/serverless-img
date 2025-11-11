#!/bin/bash

# ==============================================================================
# Script de Arranque v10 (Definitivo) para Morpheus AI Suite
# Instala todas las dependencias (sistema y Python), utiliza un caché
# pre-poblado y corrige el contexto de ejecución para el handler.
# ==============================================================================

set -e
set -o pipefail

# --- FASE 1: INSTALACIÓN COMPLETA DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias..."

# 1.1: Dependencias del Sistema (apt)
echo "[MORPHEUS-STARTUP]    -> Instalando 'curl' para el health check..."
apt-get update && apt-get install -y curl

# 1.2: Dependencias de Python (pip) para Nodos Personalizados
echo "[MORPHEUS-STARTUP]    -> Instalando dependencias de Python (insightface y onnxruntime-gpu)..."
# [CORRECCIÓN] Instalamos 'onnxruntime-gpu' explícitamente, que es requerido por 'insightface'
pip install insightface onnxruntime-gpu

echo "[MORPHEUS-STARTUP]    -> Dependencias instaladas."

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v10 (DEFINITIVO)   ---"
echo "====================================================================="

# --- FASE 2: CONFIGURACIÓN DE RUTAS Y ENTORNO ---
echo "[MORPHEUS-STARTUP] FASE 2: Configurando rutas y entorno..."
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
CONFIG_SOURCE_DIR="/workspace/morpheus_config"
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"

NETWORK_VOLUME_PATH="/runpod-volume"
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"

if [ ! -d "$CACHE_DIR" ]; then
    echo "[MORPHEUS-STARTUP] ¡ERROR FATAL! El directorio de caché '${CACHE_DIR}' no se encuentra."
    exit 1
fi
echo "[MORPHEUS-STARTUP]    -> Directorio de caché encontrado en '${CACHE_DIR}'."

mkdir -p "${CUSTOM_NODES_DIR}" "${MODELS_DIR}" "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "[MORPHEUS-STARTUP]    -> Estructura de directorios y workflows lista."

# --- FASE 3: ENLACE SIMBÓLICO DESDE EL CACHÉ ---
echo "[MORPHEUS-STARTUP] FASE 3: Creando enlaces simbólicos desde el caché..."
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
echo "[MORPHEUS-STARTUP]    -> Enlaces simbólicos completados."

# --- FASE 4: INICIO DE SERVICIOS ---
echo "[MORPHEUS-STARTUP] FASE 4: Iniciando servicios..."
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado. Esperando a que esté listo..."

# Health Check
TIMEOUT=120; ELAPSED=0
while true; do
    if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then
        echo "[MORPHEUS-STARTUP]    -> ¡Servidor de ComfyUI está listo!"; break
    else
        echo "[MORPHEUS-STARTUP]    -> Esperando a ComfyUI..."
    fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "[MORPHEUS-STARTUP] ¡ERROR FATAL! ComfyUI no respondió en ${TIMEOUT}s."; exit 1
    fi
    sleep 3; ELAPSED=$((ELAPSED + 3))
done

echo "====================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"
echo "====================================================================="

# --- FASE 5: INICIO DEL HANDLER PERSONALIZADO ---
# [CORRECCIÓN DEFINITIVA] Cambiamos al directorio raíz ANTES de ejecutar el script.
# Esto asegura que el directorio actual (/) esté en el PYTHONPATH,
# permitiendo que 'morpheus_handler.py' encuentre e importe 'comfy_handler.py'.
cd /

echo "[MORPHEUS-STARTUP] Iniciando el handler personalizado de Morpheus desde el directorio raíz..."
exec python3 -u "${CONFIG_SOURCE_DIR}/morpheus_handler.py"
wait -n
exit $?
