#!/bin/bash

# ==============================================================================
# Script de Arranque v2 (Optimizado con Cacheo) para Morpheus AI Suite
# ==============================================================================
# Este script ahora utiliza el Network Volume montado en /workspace/job_data
# como un caché persistente para los modelos de IA. Esto reduce drásticamente
# el tiempo de "arranque en frío" de los workers.
# ==============================================================================

set -e

echo "===================================================================="
echo "--- INICIANDO CONFIGURACIÓN v2 (CON CACHÉ) DE MORPHEUS (IMG) ---"
echo "===================================================================="

# --- DEFINICIÓN DE VARIABLES DE DIRECTORIO ---
COMFYUI_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
CONFIG_SOURCE_DIR="/workspace/morpheus_config"
WORKFLOWS_DEST_DIR="/workspace/morpheus_lib/workflows"

# --- [NUEVO] Directorio de Caché en el Volumen Persistente ---
# Este directorio reside en el Network Volume que montamos en /workspace/job_data
CACHE_DIR="/workspace/job_data/model_cache"

echo "1. Asegurando que los directorios de destino y caché existan..."
mkdir -p "${CUSTOM_NODES_DIR}"
mkdir -p "${MODELS_DIR}/checkpoints"
mkdir -p "${MODELS_DIR}/ipadapter"
mkdir -p "${MODELS_DIR}/controlnet"
mkdir -p "${WORKFLOWS_DEST_DIR}"
# Creamos también los subdirectorios correspondientes en el caché
mkdir -p "${CACHE_DIR}/checkpoints"
mkdir -p "${CACHE_DIR}/ipadapter"
mkdir -p "${CACHE_DIR}/controlnet"
echo "   Directorios listos."

echo "2. Copiando archivos de workflow .json..."
cp "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "   Workflows copiados con éxito."

# --- FUNCIÓN DE DESCARGA ---
download_file() {
    local url="$1"
    local dest_path="$2"
    echo "   Descargando desde: ${url}"
    echo "   Hacia (caché): ${dest_path}"
    wget --quiet --show-progress --follow-redirects -O "${dest_path}" "${url}"
    echo "   Descarga a caché completa."
}

# --- PROCESAMIENTO DEL ARCHIVO DE RECURSOS ---
echo "3. Procesando 'morpheus_resources_image.txt' para instalar dependencias..."
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"

if [ ! -f "$RESOURCE_FILE" ]; then
    echo "   ¡ERROR CRÍTICO! No se encontró el archivo de recursos en ${RESOURCE_FILE}."
    exit 1
fi

grep -v '^#' "$RESOURCE_FILE" | while IFS=, read -r type name url; do
    type=$(echo "$type" | xargs)
    name=$(echo "$name" | xargs)
    url=$(echo "$url" | xargs)

    if [ -z "$type" ]; then continue; fi

    echo "   Procesando entrada: TIPO=[${type}], NOMBRE=[${name}]"

    case "$type" in
        GIT)
            DEST_DIR="${CUSTOM_NODES_DIR}/${name}"
            if [ -d "$DEST_DIR" ]; then
                echo "   -> El nodo '${name}' ya existe. Omitiendo."
            else
                echo "   -> Clonando nodo '${name}' desde ${url}..."
                git clone "${url}" "${DEST_DIR}"
                echo "   -> Clonación completada."
            fi
            ;;

        URL_AUTH | MODEL)
            # Unificamos la lógica para todos los modelos que se descargan.
            if [ "$type" == "URL_AUTH" ]; then
                MODEL_FOLDER=$(dirname "${name}") # ej: checkpoints/talmendoxl... -> checkpoints
                FILENAME=$(basename "${name}") # ej: checkpoints/talmendoxl... -> talmendoxl...
                DOWNLOAD_URL=$url
            else # Es tipo MODEL
                # Leemos la línea con el formato correcto para este caso
                IFS=, read -r _ MODEL_FOLDER HF_REPO FILENAME <<< "$type,$name,$url"
                MODEL_FOLDER=$(echo "$MODEL_FOLDER" | xargs)
                HF_REPO=$(echo "$HF_REPO" | xargs)
                FILENAME=$(echo "$FILENAME" | xargs)
                DOWNLOAD_URL="https://huggingface.co/${HF_REPO}/resolve/main/${FILENAME}"
            fi

            DEST_FILE="${MODELS_DIR}/${MODEL_FOLDER}/${FILENAME}"
            CACHE_FILE="${CACHE_DIR}/${MODEL_FOLDER}/${FILENAME}"

            if [ -f "$CACHE_FILE" ]; then
                echo "   -> Modelo '${FILENAME}' encontrado en el caché."
            else
                echo "   -> Modelo '${FILENAME}' NO encontrado en el caché. Descargando..."
                # Descargamos el archivo directamente al directorio de caché
                download_file "${DOWNLOAD_URL}" "${CACHE_FILE}"
            fi

            # Creamos un enlace simbólico desde la ubicación del caché a donde ComfyUI espera el archivo.
            # 'ln -sf' crea el enlace ('s') y lo sobreescribe si ya existe ('f'). Es seguro ejecutarlo siempre.
            echo "   -> Creando enlace simbólico: ${DEST_FILE} -> ${CACHE_FILE}"
            ln -sf "${CACHE_FILE}" "${DEST_FILE}"
            ;;
        *)
            echo "   -> Tipo de recurso desconocido: '${type}'. Omitiendo."
            ;;
    esac
done

echo "===================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS (v2) COMPLETADA CON ÉXITO ---"
echo "===================================================================="
