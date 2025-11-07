# Guía de Despliegue del Microservicio de Imágenes en RunPod

**Versión 3.2 (Verificación Manual por Comandos y URLs Corregidas)**

Este documento detalla el proceso paso a paso para desplegar el microservicio de imágenes de Morpheus AI Suite. Esta guía incluye la configuración del almacenamiento persistente y una estrategia de cacheo de modelos para un rendimiento óptimo.

## Arquitectura de Despliegue Optimizada

Este microservicio utiliza el **Network Volume** de RunPod no solo para los archivos de los trabajos, sino también como un **caché persistente para los modelos de IA**.

-   **Problema (Arranque en Frío):** Sin cacheo, cada nuevo worker debe descargar gigabytes de modelos desde internet, causando un retraso de varios minutos en el primer trabajo del día.
-   **Solución (Cacheo):**
    1.  El **primer worker** que se inicia descarga los modelos y los guarda en el Network Volume persistente.
    2.  **Todos los workers siguientes** detectan que los modelos ya existen en el volumen y, en lugar de descargarlos, crean un "acceso directo" (enlace simbólico) de forma instantánea.
-   **Resultado:** El tiempo de arranque de nuevos workers se reduce de minutos a **segundos**, mejorando drásticamente la capacidad de respuesta del sistema y la experiencia del usuario.

El script `pod_start.sh` de este repositorio ya implementa esta lógica de cacheo de forma automática.

## Prerrequisitos

- Una cuenta activa en [RunPod](https://runpod.io).
- El repositorio `ceutaseguridad/serverless-img` debe estar accesible públicamente en GitHub.

---

## Pasos de Despliegue

### Paso 1: Crear el Almacenamiento Persistente (Network Volume)

1.  **Navegar a `Storage` -> `Network Volumes`**.
2.  **Crear un Nuevo Volumen:**
    -   Nombre: `morpheus-microservices-storage`
    -   Tamaño: `20` GB (o más, para alojar los modelos y los trabajos).
    -   Ubicación: La misma que la del endpoint.
3.  **Confirmar la Creación.**

### Paso 2: Desplegar el Endpoint Serverless

1.  **Navegar a `Serverless` -> `+ New Endpoint`**.
2.  **Plantilla:** `RunPod ComfyUI`.
3.  **GPU:** `NVIDIA GeForce RTX 4090`.
4.  **Workers:** `Max: 5`, `Min: 0`, `Idle Timeout: 5`.
5.  **Enlazar Volumen de Almacenamiento:**
    -   En `Volume Mounts`, haz clic en `+ Add Mount`.
    -   **Volume:** Selecciona `morpheus-microservices-storage`.
    -   **Mount Path:** Escribe exactamente ` /workspace/job_data`.
6.  **Comando de Inicio del Contenedor:**
    ```bash
    git clone https://github.com/ceutaseguridad/serverless-img /workspace/morpheus_config && cd /workspace/morpheus_config && chmod +x pod_start.sh && ./pod_start.sh
    ```
7.  **Desplegar.**

### Paso 3: Conexión con la Aplicación Local

1.  **Obtener las URLs del Endpoint** (Worker: `...-8188...`, Fileserver: `...-8000...`) a partir de su ID.
2.  **Nota sobre Redes y Puertos:** No es necesario abrir ningún puerto. RunPod gestiona la conectividad a través de un proxy seguro usando el puerto estándar HTTPS (443).
3.  **Actualizar `config.py`** local con estas URLs para los `job_type` de `image`, `dataset` y `training`.
4.  **Reiniciar y Probar.**

---

## Proceso de Verificación Manual (Opcional pero Recomendado)

Este proceso valida que todas las URLs y rutas son correctas y "pre-calienta" el caché de modelos en el Network Volume, haciendo que el primer arranque del worker serverless sea casi instantáneo.

### 1. Iniciar un Pod de Prueba
- Ve a `Community Cloud` o `Secure Cloud` y elige una GPU de bajo coste (ej. RTX 3070).
- Usa la plantilla **`RunPod Pytorch 2`**.
- En "Volume Mounts", monta tu volumen `morpheus-microservices-storage` en la ruta `/workspace`.
- Inicia el pod y conéctate a él vía **Web Terminal**.

### 2. Ejecutar los Comandos de Descarga
- Una vez en la terminal, crea un directorio de prueba y entra en él:
  ```bash
  mkdir -p /workspace/test_downloads && cd /workspace/test_downloads
A continuación, ejecuta los siguientes comandos uno por uno para clonar los nodos y descargar todos los modelos:
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
Descargar Modelos:
code
Bash
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
3. Verificar la Estructura de Archivos
Una vez finalizadas las descargas, ejecuta ls -R para listar todos los archivos y carpetas.
Confirma que la estructura de directorios (checkpoints/, ipadapter/, etc.) y los archivos dentro de ellas son correctos.
4. Limpieza
Una vez satisfecho con la verificación, puedes terminar y destruir el pod de prueba.
Los archivos descargados permanecerán en tu Network Volume, listos para ser usados como caché por el endpoint serverless.
