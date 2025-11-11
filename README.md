# Manual de Despliegue: Microservicio de Imágenes Morpheus

**Versión 4.0 (Proceso Completo y Verificado)**

Este documento es el manual de operaciones completo para el despliegue del microservicio de imágenes de Morpheus AI Suite. El proceso está dividido en dos fases críticas:

1.  **Fase de Preparación:** Creación de un almacenamiento persistente y llenado manual de un "caché" con todos los modelos de IA necesarios. Este paso se realiza en un pod temporal de bajo coste para garantizar que todas las URLs son correctas y los archivos están en su sitio, eliminando cualquier incertidumbre.
2.  **Fase de Despliegue:** Creación de un Endpoint Serverless de alto rendimiento que se enlaza al almacenamiento "pre-calentado" de la Fase 1.

Seguir este manual garantiza un despliegue rápido, eficiente y verificado.

---

## FASE 1: PREPARACIÓN Y LLENADO DEL CACHÉ

**Objetivo:** Crear un disco de red persistente y llenarlo con todos los modelos y nodos de ComfyUI, verificando cada paso manualmente.

### Paso 1.1: Crear el Almacenamiento Persistente (Network Volume)

1.  **Navegar a `Storage` -> `Network Volumes`** en la interfaz de RunPod.
2.  **Crear un Nuevo Volumen:**
    -   **Nombre del Volumen:** `morpheus-microservices-storage`
    -   **Tamaño del Volumen (GB):** `20` GB (o más, para alojar modelos y trabajos).
    -   **Ubicación (Data Center):** Elige una ubicación (ej. `EU-RO-1`), y recuerda usar la misma para el endpoint.
3.  **Confirmar la Creación.** Anota el ID de tu volumen (ej. `yt64li1xiv`).

### Paso 1.2: Iniciar un Pod de Prueba (Banco de Pruebas)

1.  **Navegar a `Community Cloud` o `Secure Cloud`** y elige una GPU de bajo coste (ej. RTX 3070).
2.  **Seleccionar Plantilla:** Usa **`RunPod Pytorch 2`**.
3.  **Enlazar Volumen:** En la sección **"Volume Mounts"**, enlaza el volumen `morpheus-microservices-storage` a la ruta de montaje (Mount Path) `/workspace`.
4.  **Desplegar el Pod.**

### Paso 1.3: Conectar y Descargar Dependencias

1.  Una vez el pod esté en estado `Running`, conéctate a él vía **Web Terminal**.
2.  Dentro de la terminal, crea un directorio de trabajo limpio dentro del volumen de red:
    ```bash
    mkdir -p /workspace/model_cache && cd /workspace/model_cache
    ```
    *(Nota: Lo llamamos `model_cache` para que coincida con la ruta que usará el script `pod_start.sh` del serverless).*
3.  Ejecuta los siguientes comandos **uno por uno** para clonar los nodos y descargar todos los modelos.

    **Clonar Nodos Personalizados:**
    ```bash
    git clone https://github.com/ltdrdata/ComfyUI-Manager ./ComfyUI-Manager
    git clone https://github.com/ceutaseguridad/PuLID_ComfyUI ./ComfyUI-PuLID
    git clone https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet.git ./ComfyUI-Advanced-ControlNet
    ```

    **Crear Directorios para Modelos:**
    ```bash
    mkdir -p ./checkpoints ./ipadapter ./controlnet
    ```

    **Descargar Modelos (URLs Verificadas):**
    ```bash
    # Checkpoint principal
    wget --progress=bar:force -O ./checkpoints/talmendoxl_v11_beta.safetensors https://civitai.com/api/download/models/131960

    # Modelo PuLID (Requiere autenticación de Hugging Face)
    # 1. Ve a https://huggingface.co/settings/tokens para crear un token con rol "read".
    # 2. Reemplaza <PEGA_TU_TOKEN_HF_AQUÍ> con tu token.
    wget --progress=bar:force --header="Authorization: Bearer <PEGA_TU_TOKEN_HF_AQUÍ>" -O ./ipadapter/ip-adapter_pulid_sdxl_fp16.safetensors https://huggingface.co/huchenlei/ipadapter_pulid/resolve/main/ip-adapter_pulid_sdxl_fp16.safetensors

    # Modelo FaceID (se renombra a .bin por compatibilidad con el workflow)
    wget --progress=bar:force -O ./ipadapter/ip-adapter-plus-face_sdxl.bin https://huggingface.co/InvokeAI/ip-adapter-plus-face_sdxl_vit-h/resolve/main/ip-adapter-plus-face_sdxl_vit-h.safetensors

    # Modelos de ControlNet
    wget --progress=bar:force -O ./controlnet/control_v11p_sd15_openpose.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_openpose.pth
    wget --progress=bar:force -O ./controlnet/control_v11f1p_sd15_depth.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11f1p_sd15_depth.pth
    wget --progress=bar:force -O ./controlnet/control_v11p_sd15_canny.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_canny.pth
    wget --progress=bar:force -O ./controlnet/control_v11p_sd15_scribble.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_scribble.pth
    ```

### Paso 1.4: Verificar y Limpiar

1.  Una vez finalizadas las descargas, ejecuta `ls -R` para listar todos los archivos y carpetas. Confirma que la estructura es la correcta.
2.  Cuando estés satisfecho, **termina y destruye el pod de prueba**. Los archivos permanecerán seguros en el Network Volume.

---

## FASE 2: DESPLIEGUE DEL ENDPOINT SERVERLESS

**Objetivo:** Lanzar el microservicio de producción, enlazándolo al caché de modelos que hemos preparado y verificado.

### Paso 2.1: Iniciar la Creación del Endpoint

1.  **Navegar a `Serverless` -> `+ New Endpoint`**.
2.  **Seleccionar Plantilla:** `RunPod ComfyUI`.
3.  **Elegir GPU:** `NVIDIA GeForce RTX 4090` (o la deseada para producción).
4.  **Configurar Workers:** `Max: 5`, `Min: 0`, `Idle Timeout: 5`.

### Paso 2.2: Enlazar el Almacenamiento Pre-calentado

1.  Busca la sección **"Volume Mounts"**.
2.  Haz clic en `+ Add Mount`.
3.  **Volume:** Selecciona tu volumen `morpheus-microservices-storage`.
4.  **Mount Path:** Escribe exactamente ` /workspace/job_data`.
    -   *Explicación:* Esto conecta nuestro disco, que ya contiene `/model_cache`, a la ruta que el `pod_start.sh` espera.

### Paso 2.3: Configurar el Comando de Inicio

1.  Copia y pega el siguiente comando en el campo `Container Start Command`.
    ```bash
    set -e && \
echo "--- [MORPHEUS DEBUG] Iniciando comando de arranque ---" && \
git clone https://github.com/ceutaseguridad/serverless-img.git && \
cd serverless-img && \
echo "--- [MORPHEUS DEBUG] Repositorio clonado. Contenido del directorio: ---" && \
ls -l && \
echo "--- [MORPHEUS DEBUG] Intentando iniciar el handler de Python... ---" && \
python -u morpheus_handler.py

### Paso 2.4: Desplegar y Conectar

1.  **Desplegar el Endpoint.** Espera a que su estado sea "Active".
2.  **Obtener las URLs** a partir del ID del endpoint (Worker: `...-8188...`, Fileserver: `...-8000...`).
3.  **Actualizar el archivo `config.py`** local con estas URLs para los `job_type` de `image`, `dataset` y `training`.
4.  **Reiniciar la aplicación local (Streamlit y Celery) y probar.**
