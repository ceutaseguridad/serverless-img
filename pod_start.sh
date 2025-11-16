#!/bin/bash

# ==============================================================================
# Script de Arranque v24 (Soporte para InstantID y Dependencias Dinámicas)
# ==============================================================================

set -e
set -o pipefail

# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS GLOBALES ---
echo "[MORPHEUS-STARTUP] FASE 1: Instalando dependencias globales..."
apt-get update > /dev/null 2>&1 && apt-get install -y build-essential python3-dev curl unzip git > /dev/null 2>&1
pip install --upgrade pip

echo "[MORPHEUS-STARTUP]    -> Forzando instalación de insightface y onnxruntime..."
# Nota: InstantID recomienda onnxruntime-gpu 1.16.3. Lo fijamos aquí.
pip install --upgrade --no-cache-dir --force-reinstall insightface==0.7.3 onnxruntime-gpu==1.16.3 facexlib timm ftfy requests xformers "huggingface-hub<1.0"
echo "[MORPHEUS-STARTUP]    -> Dependencias globales instaladas."

echo "====================================================================="
echo "--- [MORPHEUS-STARTUP] INICIANDO CONFIGURACIÓN v24 ---"
echo "====================================================================="

# --- FASE 2: DEFINICIÓN DE RUTAS ---
CONFIG_SOURCE_DIR="/workspace/morpheus_config"
NETWORK_VOLUME_PATH="/runpod-volume"
CACHE_DIR="${NETWORK_VOLUME_PATH}/morpheus_model_cache"
WORKFLOWS_DEST_DIR="${NETWORK_VOLUME_PATH}/morpheus_lib/workflows"
COMFYUI_DIR="/comfyui"
CUSTOM_NODES_DIR="${COMFYUI_DIR}/custom_nodes"
MODELS_DIR="${COMFYUI_DIR}/models"
echo "[MORPHEUS-STARTUP] FASE 2: Rutas definidas."

# --- FASE 3: VERIFICACIÓN DEL VOLUMEN ---
echo "[MORPHEUS-STARTUP] FASE 3: Esperando volumen persistente..."
WAIT_TIMEOUT=60; ELAPSED=0
while [ ! -d "$CACHE_DIR" ]; do
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then echo "¡ERROR FATAL! '${CACHE_DIR}' no apareció."; exit 1; fi
    echo -n "."; sleep 2; ELAPSED=$((ELAPSED + 2))
done
echo " ¡Volumen persistente verificado!"

# --- FASE 4: PREPARACIÓN DEL ENTORNO ---
echo "[MORPHEUS-STARTUP] FASE 4: Preparando entorno y creando enlaces simbólicos..."
mkdir -p "${WORKFLOWS_DEST_DIR}"
cp -v "${CONFIG_SOURCE_DIR}/workflows/"*.json "${WORKFLOWS_DEST_DIR}/"
cp /handler.py "${CONFIG_SOURCE_DIR}/comfy_handler.py"

RESOURCE_FILE="${CONFIG_SOURCE_DIR}/morpheus_resources_image.txt"
while IFS=, read -r type name url || [[ -n "$type" ]]; do
    [[ "$type" =~ ^# ]] || [[ -z "$type" ]] && continue
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs)
    # Ruta del recurso en el almacenamiento persistente (visto desde el worker)
    SOURCE_PATH="${CACHE_DIR}/${name}"
    
    case "$type" in
        GIT)
            # El destino para los nodos GIT es siempre custom_nodes
            DEST_PATH="${CUSTOM_NODES_DIR}/${name}";
            if [ -d "$SOURCE_PATH" ]; then
                ln -sf "${SOURCE_PATH}" "${DEST_PATH}";
                echo "[MORPHEUS-STARTUP]    -> Enlace GIT creado para '${name}'."
            fi
            ;;
        URL_AUTH)
            # Para URL_AUTH, el nombre es la carpeta de destino dentro de 'models'
            DEST_FOLDER_PATH="${MODELS_DIR}/${name}";
            if [ -d "$SOURCE_PATH" ]; then
                mkdir -p "$DEST_FOLDER_PATH";
                # Enlazamos el contenido de la carpeta de origen a la de destino
                ln -sf "${SOURCE_PATH}"/* "${DEST_FOLDER_PATH}/";
                 echo "[MORPHEUS-STARTUP]    -> Enlace de Modelos creado para la carpeta '${name}'."
            fi
            ;;
    esac
done < <(grep -v '^#' "$RESOURCE_FILE" | awk -F, '!seen[$1,$2]++')
echo "[MORPHEUS-STARTUP]    -> Enlaces completados."


# ==============================================================================
# FASE 4.6: INSTALAR DEPENDENCIAS DE NODOS PERSONALIZADOS (NUEVO)
# ==============================================================================
# Busca archivos requirements.txt en los nodos enlazados e instala sus dependencias.

echo "[MORPHEUS-STARTUP] FASE 4.6: Instalando dependencias de nodos personalizados..."
for req_file in $(find "${CUSTOM_NODES_DIR}" -maxdepth 2 -name "requirements.txt"); do
    node_name=$(basename $(dirname "$req_file"))
    echo "[MORPHEUS-STARTUP]    -> Instalando dependencias para el nodo '${node_name}'..."
    pip install -r "$req_file"
done
echo "[MORPHEUS-STARTUP]    -> Dependencias de nodos finalizadas."
# ==============================================================================


# --- FASE 5: INICIO DE SERVICIOS ---
echo "[MORPHEUS-STARTUP] FASE 5: Iniciando servicios..."
python3 "${COMFYUI_DIR}/main.py" --listen --port 8188 --verbose &
echo "[MORPHEUS-STARTUP]    -> Servidor de ComfyUI iniciado."

TIMEOUT=180; ELAPSED=0
while true; do
    if curl -s --head http://127.0.0.1:8188/ | head -n 1 | grep "200 OK" > /dev/null; then echo; echo "[MORPHEUS-STARTUP] -> ¡Servidor de ComfyUI está listo!"; break; else echo -n "."; fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then echo "¡ERROR FATAL! ComfyUI no respondió."; exit 1; fi
    sleep 3; ELAPSED=$((ELAPSED + 3))
done

echo "====================================================================="
echo "--- CONFIGURACIÓN DE MORPHEUS COMPLETADA CON ÉXITO ---"
echo "====================================================================="

# --- FASE 6: INICIO DEL HANDLER DE MORPHEUS ---
cd "${CONFIG_SOURCE_DIR}"
echo "[MORPHEUS-STARTUP] Iniciando el handler 'morpheus_handler.py'..."
exec python3 -u morpheus_handler.py
