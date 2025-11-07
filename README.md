# Guía de Despliegue del Microservicio de Imágenes en RunPod

**Versión 3.0 (Definitiva con Estrategia de Cacheo y Detalles Completos)**

Este documento detalla el proceso paso a paso para desplegar el microservicio de imágenes de Morpheus AI Suite como un Endpoint Serverless en la plataforma RunPod. Esta guía incluye la configuración del almacenamiento persistente y una estrategia de cacheo de modelos para un rendimiento óptimo.

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

El almacenamiento persistente es **esencial** para el cacheo de modelos y para que los archivos de entrada/salida no se borren cuando los workers se apaguen.

1.  **Navegar a la Sección de Almacenamiento:**
    -   En el panel de la izquierda, haz clic en `Storage` -> `Network Volumes`.
2.  **Crear un Nuevo Volumen:**
    -   Haz clic en `+ New Volume`.
    -   **Nombre del Volumen:** `morpheus-microservices-storage` (o un nombre descriptivo similar).
    -   **Tamaño del Volumen (GB):** Se recomienda empezar con `20` GB. Este tamaño debe ser suficiente para alojar los modelos y los archivos de los trabajos. Se puede redimensionar más tarde.
    -   **Ubicación (Data Center):** **Importante:** Elige la misma ubicación donde planeas desplegar el endpoint (ej. `US East`) para minimizar la latencia.
3.  **Confirmar la Creación:**
    -   Haz clic en `Create Volume`. Ahora tendrás un disco de red listo para ser usado.

### Paso 2: Desplegar el Endpoint Serverless

1.  **Navegar a la Sección Serverless:**
    -   En el panel de la izquierda, haz clic en **Serverless**.
    -   En la página de `Endpoints`, haz clic en el botón **+ New Endpoint**.
2.  **Seleccionar la Plantilla:**
    -   Busca en la lista de plantillas y selecciona **`RunPod ComfyUI`**.
3.  **Elegir una GPU:**
    -   Se recomienda **NVIDIA GeForce RTX 4090** para un buen rendimiento.
4.  **Configurar los Workers:**
    -   **Max Workers:** `5` (o un número adecuado a la carga esperada).
    -   **Min Workers:** `0`. **¡Esencial para la eficiencia de costes!** El servicio escalará a cero cuando esté inactivo.
    -   **Idle Timeout:** `5` (minutos). Un worker se apagará automáticamente tras 5 minutos de inactividad.
5.  **Enlazar el Volumen de Almacenamiento (Paso Clave):**
    -   Busca la sección **"Volume Mounts"**.
    -   Haz clic en `+ Add Mount`.
    -   **Volume:** En el desplegable, selecciona el volumen que creaste en el Paso 1 (`morpheus-microservices-storage`).
    -   **Mount Path:** Escribe exactamente ` /workspace/job_data`.
        -   *Explicación:* El `file_server` dentro de la plantilla está programado para guardar todas las subidas y resultados en esta ruta. Nuestro script `pod_start.sh` también usará esta ruta para el caché de modelos.
6.  **Establecer el Comando de Inicio del Contenedor:**
    -   Copia y pega el siguiente comando **exactamente como está** en el campo `Container Start Command`:
    ```bash
    git clone https://github.com/ceutaseguridad/serverless-img /workspace/morpheus_config && cd /workspace/morpheus_config && chmod +x pod_start.sh && ./pod_start.sh
    ```
7.  **Desplegar:**
    -   Haz clic en el botón **Deploy**.
    -   El endpoint pasará a un estado "Initializing". Puedes monitorizar el proceso de arranque en la pestaña `Logs` del endpoint. El primer arranque será más lento mientras se llena el caché de modelos.

---

## Paso 3: Conexión con la Aplicación Local

Una vez que el estado del endpoint en RunPod cambie a **"Active"**, sigue estos pasos:

### 1. Obtener las URLs del Endpoint
- Haz clic en tu nuevo endpoint para ver sus detalles y obtener su **ID** (ej: `a1b2c3d4e5f6`).
- Construye las dos URLs necesarias a partir de este ID:
  -   **Worker URL (API):** `https://<ID_DEL_ENDPOINT>-8188.proxy.runpod.net`
  -   **Fileserver URL (Archivos):** `https://<ID_DEL_ENDPOINT>-8000.proxy.runpod.net`

### 2. Nota Importante sobre Redes y Puertos
**No es necesario abrir ni configurar ningún puerto manualmente.** La plataforma RunPod gestiona toda la conectividad de red a través de un proxy seguro.

-   Tu aplicación local se comunica con las URLs de RunPod a través del puerto estándar **HTTPS (443)**, que está permitido por defecto en todas las redes.
-   El proxy de RunPod recibe estas peticiones y las redirige internamente a los puertos correctos (`8188` para el worker, `8000` para el fileserver) dentro del contenedor.
-   Toda la complejidad de la red es abstraída por la plataforma.

### 3. Actualizar la Configuración Local
- Abre el archivo `config.py` en tu proyecto Morpheus.
- Modifica el diccionario `MICROSERVICE_ENDPOINTS` para que apunte a las URLs que has construido. Los `job_type` relevantes para este servicio son `image`, `dataset` y `training`.```python
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
4. Reiniciar y Probar
Reinicia tu aplicación local (Streamlit y Celery).
Lanza un trabajo desde "Texto a Imagen". Ahora será procesado por tu microservicio optimizado.
