Manual de Despliegue: Microservicio de Imágenes Morpheus
Versión 5.0 (Proceso Final y Verificado)
Este documento es el manual de operaciones completo para el despliegue del microservicio de imágenes de Morpheus AI Suite. El proceso está dividido en dos fases críticas:
Fase de Preparación: Creación de un almacenamiento persistente y llenado manual de un "caché" con todos los modelos y nodos de IA necesarios. Este paso se realiza en un pod temporal de bajo coste para garantizar que todas las URLs son correctas y los archivos están en su sitio.
Fase de Despliegue: Creación de un Endpoint Serverless de alto rendimiento que se enlaza al almacenamiento "pre-calentado" de la Fase 1, utilizando un script de arranque personalizado para una configuración automática y robusta.
Seguir este manual garantiza un despliegue rápido, eficiente y verificado.
FASE 1: PREPARACIÓN Y LLENADO DEL CACHÉ DE MODELOS
Objetivo: Crear un disco de red persistente y llenarlo con todos los modelos y nodos de ComfyUI.
Paso 1.1: Crear el Almacenamiento Persistente (Network Volume)
Navega a Storage -> Network Volumes en la interfaz de RunPod.
Crea un Nuevo Volumen:
Nombre del Volumen: morpheus-microservices-storage (o similar).
Tamaño del Volumen (GB): 30 GB (recomendado para alojar todos los modelos y futuros trabajos).
Ubicación (Data Center): Elige una ubicación (ej. EU-RO-1), y recuerda usar la misma para el endpoint.
Confirma la Creación.
Paso 1.2: Iniciar un Pod Temporal para la Preparación
Navega a Community Cloud o Secure Cloud y elige una GPU de bajo coste (ej. RTX 3070).
Selecciona la plantilla RunPod Pytorch 2 (o una similar con git y wget instalados).
Enlazar Volumen: En la sección Volume Mounts, enlaza el volumen morpheus-microservices-storage a la ruta de montaje (Mount Path) /workspace.
Despliega el Pod.
Paso 1.3: Conectar y Poblar el Caché
Una vez el pod esté en estado Running, conéctate a él vía Web Terminal.
Dentro de la terminal, crea el directorio raíz de nuestro caché. El nombre de esta carpeta es crucial.
code
Bash
mkdir -p /workspace/morpheus_model_cache && cd /workspace/morpheus_model_cache
Ejecuta los siguientes comandos uno por uno para clonar los nodos y descargar todos los modelos dentro de morpheus_model_cache.
Clonar Nodos Personalizados:
code
Bash
git clone https://github.com/ltdrdata/ComfyUI-Manager ./ComfyUI-Manager
git clone https://github.com/ceutaseguridad/PuLID_ComfyUI ./ComfyUI-PuLID
git clone https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet.git ./ComfyUI-Advanced-ControlNet
Crear Directorios para Modelos:
code
Bash
mkdir -p ./checkpoints ./ipadapter ./controlnet
Descargar Modelos (URLs Verificadas):
code
Bash
# Checkpoint principal
wget --progress=bar:force -O ./checkpoints/talmendoxl_v11_beta.safetensors https://civitai.com/api/download/models/131960

# Modelo PuLID - Usa un token de Hugging Face si tienes problemas de límite de velocidad.
wget --progress=bar:force -O ./ipadapter/ip-adapter_pulid_sdxl_fp16.safetensors https://huggingface.co/huchenlei/ipadapter_pulid/resolve/main/ip-adapter_pulid_sdxl_fp16.safetensors

# Modelo FaceID
wget --progress=bar:force -O ./ipadapter/ip-adapter-plus-face_sdxl.bin https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl.bin

# Modelos de ControlNet
wget --progress=bar:force -O ./controlnet/control_v11p_sd15_openpose.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_openpose.pth
wget --progress=bar:force -O ./controlnet/control_v11f1p_sd15_depth.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11f1p_sd15_depth.pth
wget --progress=bar:force -O ./controlnet/control_v11p_sd15_canny.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_canny.pth
wget --progress=bar:force -O ./controlnet/control_v11p_sd15_scribble.pth https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_scribble.pth
Paso 1.4: Verificar y Limpiar
Una vez finalizadas las descargas, ejecuta ls -R para listar todos los archivos y carpetas. Confirma que la estructura coincide con la del Paso 2.2 del README.md del proyecto serverless-img.
Cuando estés satisfecho, termina y destruye el pod de prueba. Los archivos permanecerán seguros en el Network Volume.
FASE 2: DESPLIEGUE DEL ENDPOINT SERVERLESS
Objetivo: Lanzar el microservicio de producción, enlazándolo al caché de modelos que hemos preparado.
Paso 2.1: Iniciar la Creación del Endpoint
Navega a Serverless -> + New Endpoint.
Select Template: Elige la plantilla oficial RunPod ComfyUI.
GPU Configuration: Elige las GPUs deseadas para producción (ej. RTX A4000).
Worker Configuration: Ajusta los valores (Max Workers, Idle Timeout, etc.).
Paso 2.2: Configuración del Docker y Comando de Inicio (Paso CRUCIAL)
En la configuración del endpoint, busca la sección Docker Configuration y haz clic en "Customize" para anular los valores por defecto.
Container Image: Verifica que la imagen sea registry.runpod.net/runpod-workers-worker-comfyui-main-dockerfile:e7c259e92 (o la versión más reciente).
Container Start Command: Pega el siguiente comando exactamente como está. Este comando descarga el código de configuración, lo hace ejecutable e inicia el script de arranque pod_start.sh.
code
Bash
bash -c "git clone https://github.com/ceutaseguridad/serverless-img.git /workspace/morpheus_config && cd /workspace/morpheus_config && chmod +x pod_start.sh && ./pod_start.sh"
Paso 2.3: Enlazar el Almacenamiento Pre-calentado
Busca la sección Network Volume.
Volume: Selecciona tu volumen morpheus-microservices-storage de la lista.
Mount Path: Escribe exactamente /runpod-volume.
Explicación: Esto conecta nuestro disco (que contiene /morpheus_model_cache) a la ruta /runpod-volume dentro del contenedor, que es la ruta que el script pod_start.sh está programado para buscar.
Paso 2.4: Desplegar y Conectar
Despliega el Endpoint. Espera a que su estado sea "Active".
Copia el ID del endpoint.
Abre el archivo config.py en tu orquestador local de Morpheus.
Actualiza el diccionario MICROSERVICE_ENDPOINTS con los datos del nuevo endpoint.
worker_url es simplemente el ID del endpoint.
fileserver_url se construye con el ID. Asumimos que el fileserver se ejecuta en el puerto 8000.
code
Python
# Ejemplo en config.py
MICROSERVICE_ENDPOINTS = {
    "image": {
        "worker_url": "tu-id-de-endpoint-aqui",
        "fileserver_url": "https://tu-id-de-endpoint-aqui-8000.proxy.runpod.net"
    },
    # ... otros endpoints
}
Reinicia tu aplicación local (Streamlit y Celery) y lanza un trabajo de prueba. ¡El sistema ahora es completamente funcional
