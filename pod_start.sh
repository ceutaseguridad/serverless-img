#!/bin/bash

# ==============================================================================
# Script de Arranque v3 (Ruta Serverless Corregida) para Morpheus AI Suite
# ==============================================================================
# Este script utiliza la ruta de montaje correcta para Network Volumes en
# Serverless (/runpod-volume) como un caché persistente para los modelos.
# ==============================================================================

set -e

echo "===================================================================="
echo "--- INICIANDO CONFIGURACIÓN v3 (Ruta /runpod-volume) DE MORPHEUS ---"
echo "===================================================================="

# --- DEFINICIÓN DE VARIABLES DE DIRECTORIO ---
COMFYUI_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
CONFIG_SOURCE_DIR="/workspace/morpheus_config"

# --- [RUTA CORREGIDA] El worker de morpheus buscará los workflows aquí ---
WORKFLOWS_DEST_DIR="/runpod-volume/morpheus_lib/workflows"

# --- [RUTA CORREGIDA] Directorio de Caché en el Volumen Persistente ---
CACHE_DIR="/runpod-volume/model_cache"

echo "1. Asegurando que los directorios de destino y caché existan..."
mkdir -p "${CUSTOM_NODES_DIR}"
mkdir -p "${MODELS_DIR}/checkpoints"
mkdir -p "${MODELS_DIR}/ipadapter"
mkdir -p "${MODELS_DIR}/controlnet"
mkdir -p "${WORKFLOWS_DEST_DIR}"
mkdir -p "${CACHE_DIR}/checkpoints"
mkdir -p "${CACHE_DIR}/ipadapter"
mkdir -p "${CACHE_DIR}/controlnet"
echo "   Directorios listos."

echo "2. Copiando archivos de workflow .json a ${WORKFLOWS_DEST_DIR}..."
cp "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "   Workflows copiados con éxito."

# ... (El resto del script de descarga y enlace simbólico no necesita cambios,
# ya que las variables CACHE_DIR y MODELS_DIR se encargan de las rutas) ...

download_file() {
    local url="$1"
    local dest_path="$2"
    echo "   Descargando desde: ${url}"
    echo "   Hacia (caché): ${dest_path}"
    wget --quiet --show-progress --follow-redirects -O "${dest_path}" "${url}"
    echo "   Descarga a caché completa."
}

echo "3. Procesando 'morpheus_resources_image.txt' para instalar dependencias..."
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
if [ ! -f "$RESOURCE_FILE" ]; then
    echo "   ¡ERROR CRÍTICO! No se encontró el archivo de recursos."
    exit 1
fi

grep -v '^#' "$RESOURCE_FILE" | while IFS=, read -r type name url; do
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs); url=$(echo "$url" | xargs)
    if [ -z "$type" ]; then continue; fi
    echo "   Procesando entrada: TIPO=[${type}], NOMBRE=[${name}]"
    case "$type" in
        GIT)
            DEST_DIR="${CUSTOM_NODES_DIR}/${name}"
            if [ -d "$DEST_DIR" ]; then echo "   -> El nodo '${name}' ya existe. Omitiendo."; else
                echo "   -> Clonando nodo '${name}'..."; git clone "${url}" "${DEST_DIR}"; echo "   -> Clonación completada."
            fi
            ;;
        URL_AUTH | MODEL)
            if [ "$type" == "URL_AUTH" ]; then
                MODEL_FOLDER=$(dirname "${name}"); FILENAME=$(basename "${name}"); DOWNLOAD_URL=$url
            else
                IFS=, read -r _ MODEL_FOLDER HF_REPO FILENAME <<< "$type,$name,$url"
                MODEL_FOLDER=$(echo "$MODEL_FOLDER" | xargs); HF_REPO=$(echo "$HF_REPO" | xargs); FILENAME=$(echo "$FILENAME" | xargs)
                DOWNLOAD_URL="https://huggingface.co/${HF_REPO}/resolve/main/${FILENAME}"
            fi
            DEST_FILE="${MODELS_DIR}/${MODEL_FOLDER}/${FILENAME}"; CACHE_FILE="${CACHE_DIR}/${MODEL_FOLDER}/${FILENAME}"
            if [ -f "$CACHE_FILE" ]; then echo "   -> Modelo '${FILENAME}' encontrado en el caché."; else
                echo "   -> Modelo '${FILENAME}' NO encontrado. Descargando..."; download_file "${DOWNLOAD_URL}" "${CACHE_FILE}"
            fi
            echo "   -> Creando enlace simbólico: ${DEST_FILE} -> ${CACHE_FILE}"; ln -sf "${CACHE_FILE}" "${DEST_FILE}"
            ;;
        *) echo "   -> Tipo de recurso desconocido: '${type}'. Omitiendo.";;
    esac
done

echo "===================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS (v3) COMPLETADA CON ÉXITO ---"
echo "===================================================================="
