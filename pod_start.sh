#!/bin/bash

# ==============================================================================
# Script de Arranque v4 (Robusto y Depurable) para Morpheus AI Suite
# ==============================================================================
# OBJETIVO:
# 1. Validar que el entorno (volumen de red, config) está presente.
# 2. Instalar nodos personalizados de ComfyUI que no estén en el caché.
# 3. Comprobar la existencia de modelos en un caché pre-calentado.
# 4. Crear enlaces simbólicos desde el caché a las carpetas de ComfyUI.
# 5. Si un modelo NO está en el caché (fallback), intentar descargarlo.
# 6. Iniciar los servidores de ComfyUI y de archivos.
# ==============================================================================

# --- CONFIGURACIÓN DE SEGURIDAD Y MANEJO DE ERRORES ---
# -e: Salir inmediatamente si un comando falla.
# -o pipefail: El código de salida de una tubería es el del último comando que falló.
set -e
set -o pipefail

echo "===================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v4 (ROBUSTA)      ---"
echo "===================================================================="

# --- DEFINICIÓN DE VARIABLES DE DIRECTORIO ---
COMFYUI_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
CONFIG_SOURCE_DIR="/workspace/morpheus_config"
RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
WORKFLOWS_DEST_DIR="/runpod-volume/morpheus_lib/workflows" # Directorio persistente para workflows

# --- RUTA CRÍTICA AL CACHÉ PRE-CALENTADO EN EL VOLUMEN DE RED ---
CACHE_DIR="/runpod-volume/model_cache"

# --- VERIFICACIONES INICIALES (SANITY CHECKS) ---
echo "[MORPHEUS-STARTUP] 1. Realizando verificaciones del entorno..."

if [ ! -d "$CONFIG_SOURCE_DIR" ]; then
    echo "[MORPHEUS-STARTUP] ¡ERROR FATAL! El directorio de configuración '${CONFIG_SOURCE_DIR}' no existe. ¿Falló el 'git clone' en el comando de inicio?"
    exit 1
fi

if [ ! -d "$CACHE_DIR" ]; then
    echo "[MORPHEUS-STARTUP] ¡ERROR FATAL! El directorio de caché '${CACHE_DIR}' no se encuentra. ¿Se montó correctamente el Volumen de Red?"
    exit 1
fi

if [ ! -f "$RESOURCE_FILE" ]; then
    echo "[MORPHEUS-STARTUP] ¡ERROR FATAL! No se encontró el archivo de recursos en '${RESOURCE_FILE}'."
    exit 1
fi
echo "[MORPHEUS-STARTUP]    -> Verificaciones superadas. Entorno detectado correctamente."

# --- CREACIÓN DE LA ESTRUCTURA DE DIRECTORIOS ---
echo "[MORPHEUS-STARTUP] 2. Asegurando que la estructura de directorios de ComfyUI exista..."
mkdir -p "${CUSTOM_NODES_DIR}"
mkdir -p "${MODELS_DIR}/checkpoints"
mkdir -p "${MODELS_DIR}/ipadapter"
mkdir -p "${MODELS_DIR}/controlnet"
mkdir -p "${WORKFLOWS_DEST_DIR}"
echo "[MORPHEUS-STARTUP]    -> Estructura de directorios lista."

# --- COPIA DE WORKFLOWS ---
echo "[MORPHEUS-STARTUP] 3. Copiando archivos de workflow .json a '${WORKFLOWS_DEST_DIR}'..."
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
echo "[MORPHEUS-STARTUP]    -> Workflows copiados."

# --- FUNCIÓN DE DESCARGA (FALLBACK) ---
download_file() {
    local url="$1"
    local dest_path="$2"
    local headers=()

    # Si la URL es de Hugging Face y la variable de entorno HF_TOKEN existe, la usamos.
    if [[ "$url" == *"huggingface.co"* ]] && [ -n "$HF_TOKEN" ]; then
        echo "[MORPHEUS-STARTUP]      -> Usando token de Hugging Face para la descarga."
        headers+=("--header=Authorization: Bearer ${HF_TOKEN}")
    else
        echo "[MORPHEUS-STARTUP]      -> Descargando sin token de autenticación."
    fi

    echo "[MORPHEUS-STARTUP]      -> Descargando desde: ${url}"
    echo "[MORPHEUS-STARTUP]      -> Hacia (caché): ${dest_path}"
    
    # Asegurarse que el directorio de destino en el caché existe
    mkdir -p "$(dirname "${dest_path}")"
    
    wget --quiet --show-progress --follow-redirects "${headers[@]}" -O "${dest_path}" "${url}"
    echo "[MORPHEUS-STARTUP]      -> Descarga a caché completa."
}

# --- PROCESAMIENTO DE DEPENDENCIAS ---
echo "[MORPHEUS-STARTUP] 4. Procesando 'morpheus_resources_image.txt' para instalar dependencias..."

# Leemos el archivo línea por línea para evitar problemas con espacios o caracteres especiales.
while IFS=, read -r type name url || [[ -n "$type" ]]; do
    # Ignorar líneas en blanco o comentarios
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue

    # Limpiar espacios en blanco
    type=$(echo "$type" | xargs)
    name=$(echo "$name" | xargs)
    url=$(echo "$url" | xargs)
    
    echo "[MORPHEUS-STARTUP]    -> Procesando: TIPO=[${type}], NOMBRE=[${name}]"

    case "$type" in
        GIT)
            DEST_DIR="${CUSTOM_NODES_DIR}/${name}"
            if [ -d "$DEST_DIR" ]; then
                echo "[MORPHEUS-STARTUP]      -> El nodo '${name}' ya existe. Omitiendo clonación."
            else
                echo "[MORPHEUS-STARTUP]      -> Clonando nodo '${name}'..."
                git clone --depth 1 "${url}" "${DEST_DIR}"
                echo "[MORPHEUS-STARTUP]      -> Clonación completada."
            fi
            ;;
        URL_AUTH | MODEL)
            if [ "$type" == "URL_AUTH" ]; then
                MODEL_FOLDER=$(dirname "${name}")
                FILENAME=$(basename "${name}")
                DOWNLOAD_URL=$url
            else
                # Este bloque es para el formato antiguo, lo mantenemos por compatibilidad.
                IFS=, read -r _ MODEL_FOLDER HF_REPO FILENAME <<< "$type,$name,$url"
                MODEL_FOLDER=$(echo "$MODEL_FOLDER" | xargs); HF_REPO=$(echo "$HF_REPO" | xargs); FILENAME=$(echo "$FILENAME" | xargs)
                DOWNLOAD_URL="https://huggingface.co/${HF_REPO}/resolve/main/${FILENAME}"
            fi
            
            DEST_FILE="${MODELS_DIR}/${MODEL_FOLDER}/${FILENAME}"
            CACHE_FILE="${CACHE_DIR}/${MODEL_FOLDER}/${FILENAME}"

            echo "[MORPHEUS-STARTUP]      -> Buscando en caché: ${CACHE_FILE}"
            
            if [ -f "$CACHE_FILE" ]; then
                echo "[MORPHEUS-STARTUP]      -> ENCONTRADO. El modelo '${FILENAME}' existe en el caché."
            else
                echo "[MORPHEUS-STARTUP]      -> NO ENCONTRADO. El modelo '${FILENAME}' no está en el caché. Intentando descarga (fallback)..."
                download_file "${DOWNLOAD_URL}" "${CACHE_FILE}"
            fi
            
            echo "[MORPHEUS-STARTUP]      -> Creando enlace simbólico: ${DEST_FILE} -> ${CACHE_FILE}"
            ln -sf "${CACHE_FILE}" "${DEST_FILE}"
            echo "[MORPHEUS-STARTUP]      -> Enlace creado."
            ;;
        *)
            echo "[MORPHEUS-STARTUP]    -> TIPO DE RECURSO DESCONOCIDO: '${type}'. Omitiendo."
            ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | grep -v '^[[:space:]]*$')


# --- INICIO DE SERVIDORES ---
echo "[MORPHEUS-STARTUP] 5. Iniciando servicios en segundo plano..."

# Iniciar el servidor de la API de ComfyUI
python3 /workspace/ComfyUI/main.py --listen --port 8188 &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado en el puerto 8188."

# Iniciar el servidor de archivos de RunPod (si existe el script)
# Asumimos que el script está en la raíz del volumen, si no, ajustar la ruta.
RP_FILE_SERVER="/runpod-volume/rp_file_server.py"
if [ -f "$RP_FILE_SERVER" ]; then
    python3 -u "$RP_FILE_SERVER" &
    echo "[MORPHEUS-STARTUP]    -> Servidor de archivos de RunPod iniciado."
else
    echo "[MORPHEUS-STARTUP]    -> ADVERTENCIA: No se encontró 'rp_file_server.py' en la raíz del volumen. No se inició el servidor de archivos."
fi

echo "===================================================================="
echo "--- [MORPHEUS-STARTUP] CONFIGURACIÓN COMPLETADA CON ÉXITO        ---"
echo "---                    El worker está listo para recibir trabajos. ---"
echo "===================================================================="

# Mantener el script en ejecución para que el contenedor no se cierre mientras
# los procesos en segundo plano están activos.
wait -n
exit $?
