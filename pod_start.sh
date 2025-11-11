#!/bin/bash

# ==============================================================================
# Script de Arranque v6 (Final) para Morpheus AI Suite
# Utiliza un caché de modelos y nodos pre-poblado en un Volumen de Red.
# ==============================================================================

set -e
set -o pipefail

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v6 (FINAL)         ---"
echo "====================================================================="

# --- DEFINICIÓN DE VARIABLES DE DIRECTORIO ---
COMFYUI_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
CONFIG_SOURCE_DIR="/workspace/morpheus_config"
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"

# --- [CORRECCIÓN FINAL] RUTA AL VOLUMEN Y AL CACHÉ PRE-POBLADO ---
NETWORK_VOLUME_PATH="/runpod-volume"
# Esta es la nueva ruta que coincide con tu carpeta renombrada.
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"

# --- VERIFICACIONES INICIALES ---
echo "[MORPHEUS-STARTUP] 1. Realizando verificaciones del entorno..."

if [ ! -d "$CACHE_DIR" ]; then
    echo "[MORPHEUS-STARTUP] ¡ERROR FATAL! El directorio de caché '${CACHE_DIR}' no se encuentra. ¿Se montó y renombró correctamente la carpeta en el Volumen de Red?"
    exit 1
fi
echo "[MORPHEUS-STARTUP]    -> Directorio de caché encontrado en '${CACHE_DIR}'."

# --- CREACIÓN DE LA ESTRUCTURA DE DIRECTORIOS NECESARIA ---
echo "[MORPHEUS-STARTUP] 2. Asegurando que la estructura de directorios de ComfyUI exista..."
mkdir -p "${CUSTOM_NODES_DIR}"
mkdir -p "${MODELS_DIR}"
mkdir -p "${WORKFLOWS_DEST_DIR}"
echo "[MORPHEUS-STARTUP]    -> Estructura de directorios lista."

# --- COPIA DE WORKFLOWS ---
echo "[MORPHEUS-STARTUP] 3. Copiando archivos de workflow .json..."
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "[MORPHEUS-STARTUP]    -> Workflows copiados."

# --- [CORRECCIÓN FINAL] ENLACE SIMBÓLICO DE MODELOS Y NODOS ---
echo "[MORPHEUS-STARTUP] 4. Creando enlaces simbólicos desde el caché al contenedor..."

while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs)

    echo "[MORPHEUS-STARTUP]    -> Procesando: [${type}] ${name}"

    case "$type" in
        GIT)
            # Para los nodos, enlazamos el directorio completo desde el caché.
            SOURCE_PATH="${CACHE_DIR}/${name}"
            DEST_PATH="${CUSTOM_NODES_DIR}/${name}"
            if [ -d "$SOURCE_PATH" ]; then
                ln -sf "${SOURCE_PATH}" "${DEST_PATH}"
                echo "[MORPHEUS-STARTUP]      -> Enlace simbólico para el nodo '${name}' creado."
            else
                echo "[MORPHEUS-STARTUP]      -> ADVERTENCIA: No se encontró el directorio del nodo '${name}' en el caché. Omitiendo."
            fi
            ;;
        URL_AUTH)
            # Para los modelos, enlazamos las carpetas de modelos desde el caché.
            MODEL_FOLDER=$(dirname "${name}")
            SOURCE_PATH="${CACHE_DIR}/${MODEL_FOLDER}"
            DEST_PATH="${MODELS_DIR}/${MODEL_FOLDER}"
            if [ -d "$SOURCE_PATH" ]; then
                # Creamos el directorio base en el contenedor y luego enlazamos el contenido.
                mkdir -p "$(dirname "${DEST_PATH}")"
                ln -sfn "${SOURCE_PATH}" "${DEST_PATH}"
                echo "[MORPHEUS-STARTUP]      -> Enlace simbólico para la carpeta de modelos '${MODEL_FOLDER}' creado."
            else
                echo "[MORPHEUS-STARTUP]      -> ADVERTENCIA: No se encontró la carpeta '${MODEL_FOLDER}' en el caché. Omitiendo."
            fi
            ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++') # awk para procesar cada tipo de carpeta una sola vez


# --- INICIO DE SERVIDORES ---
echo "[MORPHEUS-STARTUP] 5. Iniciando servicios en segundo plano..."

python3 /workspace/ComfyUI/main.py --listen --port 8188 &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado. Esperando a que esté listo..."

# HEALTH CHECK
TIMEOUT=90; ELAPSED=0
while true; do
    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8188/object_info)
    if [ "$STATUS_CODE" -eq 200 ]; then
        echo "[MORPHEUS-STARTUP]    -> ¡Servidor de ComfyUI está listo!"; break
    else
        echo "[MORPHEUS-STARTUP]    -> Esperando a ComfyUI... (Estado actual: $STATUS_CODE)"
    fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "[MORPHEUS-STARTUP] ¡ERROR FATAL! ComfyUI no respondió en ${TIMEOUT}s."; exit 1
    fi
    sleep 2; ELAPSED=$((ELAPSED + 2))
done

echo "====================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS (v6) COMPLETADA CON ÉXITO ---"
echo "====================================================================="

echo "[MORPHEUS-STARTUP] Iniciando el handler personalizado de Morpheus..."
exec python3 -u /workspace/morpheus_config/morpheus_handler.py
wait -n
exit $?
