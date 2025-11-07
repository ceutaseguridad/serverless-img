# Guía de Despliegue del Microservicio de Imágenes en RunPod

**Versión 2.0 (Incluye Configuración de Almacenamiento Persistente)**

Este documento detalla el proceso paso a paso para desplegar el microservicio de imágenes de Morpheus AI Suite como un Endpoint Serverless en la plataforma RunPod, incluyendo la configuración del almacenamiento persistente necesario.

## Propósito del Microservicio

Este servicio se encarga de todas las tareas relacionadas con la generación y manipulación de imágenes estáticas, incluyendo:
- Creación de imágenes desde texto (`creation`).
- Transferencia de identidad facial a imágenes (`image_identity_transfer`).
- Entrenamiento de Paquetes de Identidad Digital (`create_pid`).
- Control de composición mediante ControlNet.

Utiliza una plantilla pre-configurada de **ComfyUI** en RunPod, que es configurada al inicio por el script `pod_start.sh` de este repositorio.

## Prerrequisitos

- Una cuenta activa en [RunPod](https://runpod.io).
- El repositorio `ceutaseguridad/serverless-img` debe estar accesible públicamente en GitHub.

---

## Pasos de Despliegue (Arquitectura Correcta)

El proceso se divide en dos etapas principales: primero, crear el disco duro de red (Network Volume) donde se guardarán los archivos, y segundo, desplegar el servicio serverless y conectarlo a ese disco.

### Paso 1: Crear el Almacenamiento Persistente (Network Volume)

El almacenamiento persistente es **esencial** para que los archivos de entrada (subidas) y salida (resultados generados) no se borren cuando los workers se apaguen. Este servicio se crea y factura por separado.

1.  **Navegar a la Sección de Almacenamiento:**
    -   En el panel de la izquierda, haz clic en `Storage` -> `Network Volumes`.
2.  **Crear un Nuevo Volumen:**
    -   Haz clic en `+ New Volume`.
    -   **Nombre del Volumen:** `morpheus-microservices-storage` (o un nombre descriptivo similar).
    -   **Tamaño del Volumen (GB):** Se recomienda empezar con `20` GB. Se puede redimensionar más tarde.
    -   **Ubicación (Data Center):** **Importante:** Elige la misma ubicación donde planeas desplegar el endpoint (ej. `US East`) para minimizar la latencia.
3.  **Confirmar la Creación:**
    -   Haz clic en `Create Volume`. Ahora tendrás un disco de red listo para ser usado.

### Paso 2: Desplegar el Endpoint Serverless

1.  **Navegar a la Sección Serverless:**
    -   En el panel de la izquierda, haz clic en **Serverless**.
    -   En la página de `Endpoints`, haz clic en el botón **+ New Endpoint**.
2.  **Seleccionar la Plantilla:**
    -   Busca en la lista y selecciona **`RunPod ComfyUI`**.
3.  **Elegir una GPU:**
    -   Se recomienda **NVIDIA GeForce RTX 4090** para un buen rendimiento.
4.  **Configurar los Workers:**
    -   **Max Workers:** `5` (o un número adecuado a la carga esperada).
    -   **Min Workers:** `0`. **¡Esencial para la eficiencia de costes!**
    -   **Idle Timeout:** `5` (minutos).
5.  **Enlazar el Volumen de Almacenamiento (Paso Clave):**
    -   Busca la sección **"Volume Mounts"**.
    -   Haz clic en `+ Add Mount`.
    -   **Volume:** En el desplegable, selecciona el volumen que creaste en el Paso 1 (`morpheus-microservices-storage`).
    -   **Mount Path:** Escribe exactamente ` /workspace/job_data`.
        -   *Explicación:* El `file_server` dentro de la plantilla está programado para guardar todas las subidas y resultados en esta ruta. Al montar nuestro volumen aquí, nos aseguramos de que todos los archivos se guarden en nuestro disco persistente.
6.  **Establecer el Comando de Inicio del Contenedor:**
    -   Copia y pega el siguiente comando **exactamente como está** en el campo `Container Start Command`:
    ```bash
    git clone https://github.com/ceutaseguridad/serverless-img /workspace/morpheus_config && cd /workspace/morpheus_config && chmod +x pod_start.sh && ./pod_start.sh
    ```
7.  **Desplegar:**
    -   Haz clic en el botón **Deploy**.
    -   El endpoint pasará a "Initializing". Puedes monitorizar el proceso en la pestaña `Logs`.

---

## Paso 3: Conexión con la Aplicación Local

Una vez que el estado del endpoint en RunPod cambie a **"Active"**, sigue estos pasos:

1.  **Obtener las URLs del Endpoint:**
    -   Haz clic en tu nuevo endpoint para ver sus detalles y obtener su **ID** (ej: `a1b2c3d4e5f6`).
    -   Construye las dos URLs necesarias:
      -   **Worker URL (API):** `https://<ID_DEL_ENDPOINT>-8188.proxy.runpod.net`
      -   **Fileserver URL (Archivos):** `https://<ID_DEL_ENDPOINT>-8000.proxy.runpod.net`
2.  **Actualizar la Configuración Local:**
    -   Abre el archivo `config.py` en tu proyecto Morpheus.
    -   Modifica el diccionario `MICROSERVICE_ENDPOINTS` para que los `job_type` `image`, `dataset` y `training` apunten a estas nuevas URLs.
    ```python
    # Ejemplo de modificación en config.py
    MICROSERVICE_ENDPOINTS = {
        # ...
        "image": {
            "worker_url": "https://<ID_DEL_ENDPOINT>-8188.proxy.runpod.net",
            "fileserver_url": "https://<ID_DEL_ENDPOINT>-8000.proxy.runpod.net"
        },
        "dataset": {
            "worker_url": "https://<ID_DEL_ENDPOINT>-8188.proxy.runpod.net",
            "fileserver_url": "https://<ID_DEL_ENDPOINT>-8000.proxy.runpod.net"
        },
        "training": {
            "worker_url": "https://<ID_DEL_ENDPOINT>-8188.proxy.runpod.net",
            "fileserver_url": "https://<ID_DEL_ENDPOINT>-8000.proxy.runpod.net"
        },
        # ...
    }
    ```
3.  **Reiniciar y Probar:**
    -   Reinicia tu aplicación local (Streamlit y Celery).
    -   Lanza un trabajo desde "Texto a Imagen". Ahora será procesado por tu microservicio, utilizando el almacenamiento persistente que has configurado.

```bash
git clone https://github.com/ceutaseguridad/serverless-img /workspace/morpheus_config && cd /workspace/morpheus_config && chmod +x pod_start.sh && ./pod_start.sh
