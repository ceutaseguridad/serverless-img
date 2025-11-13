# Manual de Despliegue: Microservicio de Imágenes Morpheus
Versión 6.0 (Proceso Final y Verificado)

Este documento es el manual de operaciones completo para el despliegue del microservicio de imágenes de Morpheus AI Suite. El proceso está dividido en dos fases críticas:

1.  **Fase de Preparación:** Creación de un almacenamiento persistente y llenado manual de un "caché" con todos los modelos y nodos de IA necesarios.
2.  **Fase de Despliegue:** Creación de un Endpoint Serverless de alto rendimiento que se enlaza al almacenamiento "pre-calentado", utilizando un script de arranque personalizado para una configuración automática y robusta.

Seguir este manual garantiza un despliegue rápido, eficiente y verificado.

---

## FASE 1: PREPARACIÓN Y LLENADO DEL CACHÉ DE MODELOS

**Objetivo:** Crear un disco de red persistente y llenarlo con todos los modelos y nodos de ComfyUI. Este paso se realiza **una sola vez**.

### Paso 1.1: Crear el Almacenamiento Persistente (Network Volume)

1.  Navega a **Storage -> Network Volumes** en la interfaz de RunPod.
2.  Crea un **Nuevo Volumen**:
    -   **Nombre del Volumen:** `morpheus-microservices-storage` (o similar).
    -   **Tamaño del Volumen (GB):** `30` GB (recomendado para alojar todos los modelos y futuros trabajos).
    -   **Ubicación (Data Center):** Elige una ubicación (ej. `EU-RO-1`), y **recuerda usar la misma** para el endpoint.
3.  Confirma la Creación.

### Paso 1.2: Iniciar un Pod Temporal para la Preparación

1.  Navega a **Community Cloud** o **Secure Cloud** y elige una GPU de bajo coste (ej. RTX 3070).
2.  Selecciona la plantilla `RunPod Pytorch 2` (o una similar con `git` y `wget` instalados).
3.  **Enlazar Volumen:** En la sección "Volume Mounts", enlaza el volumen `morpheus-microservices-storage` a la ruta de montaje (Mount Path) `/workspace`.
4.  Despliega el Pod.

### Paso 1.3: Conectar y Poblar el Caché

1.  Una vez el pod esté en estado `Running`, conéctate a él vía **Web Terminal**.
2.  Dentro de la terminal, crea el directorio raíz de nuestro caché. El nombre de esta carpeta es crucial.
    ```bash
    mkdir -p /workspace/morpheus_model_cache && cd /workspace/morpheus_model_cache
    ```
3.  Ejecuta los siguientes comandos uno por uno para clonar los nodos y descargar todos los modelos dentro de `morpheus_model_cache`.

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

    # Modelo PuLID
    wget --progress=bar:force -O ./ipadapter/ip-adapter_pulid_sdxl_fp16.safetensors https://huggingface.co/huchenlei/ipadapter_pulid/resolve/main/ip-adapter_pulid_sdxl_fp16.safetensors

    # Modelo FaceID
    wget --progress=bar:force -O ./ipadapter/ip-adapter-plus-face_sdxl.bin https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl.bin

    # Modelos de ControlNet
    wget --progress=bar:force -O ./controlnet/control_v11p_sd15_openpose.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_openpose.pth
    wget --progress=bar:force -O ./controlnet/control_v11f1p_sd15_depth.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11f1p_sd15_depth.pth
    wget --progress=bar:force -O ./controlnet/control_v11p_sd15_canny.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_canny.pth
    wget --progress=bar:force -O ./controlnet/control_v11p_sd15_scribble.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_scribble.pth
    ```

### Paso 1.4: Verificar y Limpiar

1.  Una vez finalizadas las descargas, ejecuta `ls -R` para listar todos los archivos y carpetas y confirma que la estructura es correcta.
2.  Cuando estés satisfecho, **termina y destruye el pod de prueba**. Los archivos permanecerán seguros en el Network Volume.

---

## FASE 2: DESPLIEGUE DEL ENDPOINT SERVERLESS

**Objetivo:** Lanzar el microservicio de producción, enlazándolo al caché de modelos que hemos preparado.

### Paso 2.1: Iniciar la Creación del Endpoint

1.  Navega a **Serverless -> + New Endpoint**.
2.  **Select Template:** Elige la plantilla oficial `RunPod ComfyUI`.
3.  **GPU Configuration:** Elige las GPUs deseadas para producción (ej. `RTX A4000`).
4.  **Worker Configuration:** Ajusta los valores (`Max Workers`, `Idle Timeout`, etc.).

### Paso 2.2: Configuración del Docker y Comando de Inicio (Paso CRUCIAL)

1.  En la configuración del endpoint, busca la sección **Docker Configuration** y haz clic en "Customize" para anular los valores por defecto.
2.  **Container Image:** Verifica que la imagen sea `registry.runpod.net/runpod-workers-worker-comfyui-main-dockerfile:e7c259e92` (o la versión más reciente).
3.  **Container Start Command:** Pega el siguiente comando exactamente como está. Este comando descarga el código de configuración, lo hace ejecutable e inicia el script de arranque.
    ```bash
    bash -c "git clone https://github.com/ceutaseguridad/serverless-img.git /workspace/morpheus_config && cd /workspace/morpheus_config && chmod +x pod_start.sh && ./pod_start.sh"
    ```

### Paso 2.3: Enlazar el Almacenamiento Pre-calentado

1.  Busca la sección **Network Volume**.
2.  **Volume:** Selecciona tu volumen `morpheus-microservices-storage` de la lista.
3.  **Mount Path:** Escribe exactamente `/runpod-volume`.
    -   **Explicación:** Esto conecta nuestro disco (que contiene `/morpheus_model_cache`) a la ruta `/runpod-volume` dentro del contenedor del worker, que es la ruta que el script `pod_start.sh` está programado para buscar.

### Paso 2.4: Desplegar y Conectar

1.  **Despliega el Endpoint**. Espera a que su estado sea "Active".
2.  Copia el **ID del endpoint**.
3.  Abre el archivo `config.py` en tu **Orquestador Local** de Morpheus.
4.  Actualiza el diccionario `MICROSERVICE_ENDPOINTS` con los datos del nuevo endpoint. La `worker_url` es el ID del endpoint, y la `fileserver_url` es la URL del **Pod Gateway de Ficheros** que desplegaste previamente.
    ```python
    # Ejemplo en config.py
    MICROSERVICE_ENDPOINTS = {
        "image": {
            "worker_url": "tu-id-de-endpoint-aqui",
            "fileserver_url": "https://<id-del-pod-gateway>-8000.proxy.runpod.net"
        },
        # ... otros endpoints
    }
    ```
5.  Reinicia tu aplicación local (Streamlit y Celery) y lanza un trabajo de prueba.

---

## Lógica Final y Puntos Clave (A Fuego)

Esta sección documenta el conocimiento esencial para entender y depurar este servicio.

### 1. La Dualidad de Rutas: `/runpod-volume`

-   Este Worker Serverless ve el volumen de almacenamiento de red montado en la ruta `/runpod-volume`.
-   El Pod Gateway de Ficheros, en cambio, ve este **mismo volumen** en la ruta `/workspace`.
-   Toda la lógica de este worker está construida en torno a la ruta `/runpod-volume`.

### 2. El Flujo de Archivos es un "Pasa la Pelota"

-   El worker **nunca descarga** un archivo. Su trabajo es **generarlo**.
-   El workflow de ComfyUI genera el archivo en un **directorio temporal y efímero** dentro del contenedor (`/comfyui/output/`).
-   El `morpheus_handler.py` **mueve** (`shutil.move`) el archivo desde la ruta temporal a una ruta **persistente** en el volumen (`/runpod-volume/job_outputs/...`).
-   El handler finaliza y devuelve la ruta **persistente** (`/runpod-volume/...`) al cliente local. La responsabilidad de la descarga recae entonces en el cliente y el Pod Gateway.

### 3. El `pod_start.sh` es el Orquestador del Worker

-   El script **no descarga modelos**. En su lugar, crea **enlaces simbólicos** (`ln -sf`) desde las carpetas de modelos de ComfyUI hacia el caché que preparamos en la Fase 1 (`/runpod-volume/morpheus_model_cache/...`). Esto hace que el arranque del worker sea extremadamente rápido.
-   Primero espera a que el volumen en `/runpod-volume` sea visible para evitar errores.
-   Inicia ComfyUI en segundo plano y espera a que esté listo antes de lanzar el handler.

### 4. El `morpheus_handler.py` es un Motor de Plantillas

-   Los archivos `.json` en la carpeta `/workflows` no son workflows válidos por sí mismos, son **plantillas de texto**.
-   El handler realiza un simple **reemplazo de texto** para inyectar los parámetros del trabajo (`prompt`, `seed`, etc.) en los placeholders `__param:key__`.
-   Esto simplifica enormemente el código y evita tener que manipular la compleja estructura del grafo de ComfyUI en Python.
