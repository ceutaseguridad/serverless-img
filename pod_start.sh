#!/bin/bash

# ==============================================================================
# Script de Arranque para el Microservicio de Imágenes de Morpheus AI Suite
# ==============================================================================
# Este script se ejecuta al inicio de un worker de RunPod Serverless.
# Su propósito es configurar el entorno de ComfyUI descargando los nodos
# y modelos personalizados necesarios para las tareas de imagen.
# ==============================================================================

# --- PREÁMBULO ---
# 'set -e' asegura que el script falle inmediatamente si cualquier comando devuelve
# un código de error, lo que ayuda a depurar problemas en los logs de RunPod.
set -e

echo "=========================================================="
echo "--- INICIANDO CONFIGURACIÓN DE MORPHEUS (MICROSERVICIO DE IMAGEN) ---"
echo "=========================================================="

# --- DEFINICIÓN DE VARIABLES DE DIRECTORIO ---
# Define las rutas clave dentro del entorno de RunPod para mayor claridad.
COMFYUI_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
CONFIG_SOURCE_DIR="/workspace/morpheus_config" # Directorio donde se clona el repo de GitHub
WORKFLOWS_DEST_DIR="/workspace/morpheus_lib/workflows" # Directorio donde el worker busca los workflows

# --- PREPARACIÓN DEL ENTORNO ---
echo "1. Asegurando que los directorios de destino existan..."
mkdir -p "${CUSTOM_NODES_DIR}"
mkdir -p "${MODELS_DIR}/checkpoints"
mkdir -p "${MODELS_DIR}/ipadapter"
mkdir -p "${MODELS_DIR}/controlnet"
mkdir -p "${WORKFLOWS_DEST_DIR}"
echo "   Directorios listos."

# --- COPIA DE WORKFLOWS ---
# Copia los archivos de workflow .json desde el repositorio de configuración
# a la ubicación que el worker de Morpheus espera.
echo "2. Copiando archivos de workflow .json..."
cp "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "   Workflows copiados con éxito a ${WORKFLOWS_DEST_DIR}"

# --- FUNCIÓN DE DESCARGA ROBUSTA ---
# Función auxiliar para descargar archivos, mostrando el progreso y manejando nombres de archivo.
download_file() {
    local url="$1"
    local dest_path="$2"
    echo "   Descargando desde: ${url}"
    echo "   Hacia: ${dest_path}"
    # Usamos wget con opciones para ser silencioso pero mostrar progreso, seguir redirecciones y especificar la salida.
    wget --quiet --show-progress --follow-redirects -O "${dest_path}" "${url}"
    echo "   Descarga completa."
}

# --- PROCESAMIENTO DEL ARCHIVO DE RECURSOS ---
echo "3. Procesando 'morpheus_resources_image.txt' para instalar dependencias..."
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"

if [ ! -f "$RESOURCE_FILE" ]; then
    echo "   ¡ERROR CRÍTICO! No se encontró el archivo de recursos en ${RESOURCE_FILE}."
    exit 1
fi

# Leemos el archivo línea por línea, ignorando comentarios y líneas vacías.
grep -v '^#' "$RESOURCE_FILE" | while IFS=, read -r type name url; do
    # Limpiamos espacios en blanco de cada variable
    type=$(echo "$type" | xargs)
    name=$(echo "$name" | xargs)
    url=$(echo "$url" | xargs)

    if [ -z "$type" ]; then continue; fi # Omitir líneas vacías

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

        URL_AUTH)
            DEST_FILE="${MODELS_DIR}/${name}"
            if [ -f "$DEST_FILE" ]; then
                echo "   -> El modelo '${name}' ya existe. Omitiendo."
            else
                echo "   -> Descargando modelo '${name}'..."
                download_file "${url}" "${DEST_FILE}"
            fi
            ;;

        MODEL)
            # Formato: MODEL,folder,huggingface_user/repo,filename
            MODEL_FOLDER=$type # En este caso, 'MODEL' se solapa con el tipo, el folder es el segundo campo.
            HF_USER_REPO=$name
            FILENAME=$url
            MODEL_URL="https://huggingface.co/${HF_USER_REPO}/resolve/main/${FILENAME}"
            DEST_FILE="${MODELS_DIR}/${MODEL_FOLDER}/${FILENAME}" # ej: /models/controlnet/mi_modelo.pth
            
            # Necesitamos re-asignar la variable 'type' (primer campo) al 'folder' (segundo campo)
            # pero la lectura ya se ha hecho. Una forma más limpia sería:
            # IFS=, read -r type folder hf_repo filename
            # Por ahora, usamos el 'type' como el folder.
            
            # Corrección: El primer campo es el tipo, el segundo es la carpeta destino.
            # Vamos a releer la línea con el formato correcto para este caso.
            IFS=, read -r _ folder hf_repo filename <<< "$type,$name,$url"
            folder=$(echo "$folder" | xargs)
            hf_repo=$(echo "$hf_repo" | xargs)
            filename=$(echo "$filename" | xargs)
            
            MODEL_URL="https://huggingface.co/${hf_repo}/resolve/main/${filename}"
            DEST_FILE="${MODELS_DIR}/${folder}/${filename}"
            
            if [ -f "$DEST_FILE" ]; then
                echo "   -> El modelo '${filename}' ya existe en '${folder}'. Omitiendo."
            else
                echo "   -> Descargando modelo '${filename}' desde Hugging Face..."
                download_file "${MODEL_URL}" "${DEST_FILE}"
            fi
            ;;
        *)
            echo "   -> Tipo de recurso desconocido: '${type}'. Omitiendo."
            ;;
    esac
done

echo "=========================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"
echo "=========================================================="

# La plantilla base de RunPod se encargará ahora de iniciar los servicios
# necesarios como el servidor de ComfyUI.