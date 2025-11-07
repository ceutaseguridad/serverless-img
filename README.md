# Guía de Despliegue del Microservicio de Imágenes en RunPod

**Versión 3.1 (Añadido Proceso de Verificación Manual)**

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

Antes de desplegar el endpoint serverless, puedes verificar manualmente que todas las rutas de descarga y la estructura de directorios son correctas. Este proceso "pre-calienta" el caché, haciendo que el primer arranque del worker serverless sea instantáneo.

### 1. Iniciar un Pod de Prueba
- Ve a `Community Cloud` o `Secure Cloud` y elige una GPU de bajo coste (ej. RTX 3070).
- Usa la plantilla **`RunPod Pytorch 2`**.
- En "Volume Mounts", monta tu volumen `morpheus-microservices-storage` en la ruta `/workspace`.
- Inicia el pod y conéctate a él vía **SSH**.

### 2. Ejecutar el Script de Descarga
- Una vez en la terminal SSH del pod, crea un directorio de prueba y entra en él:
  ```bash
  mkdir -p /workspace/test_downloads && cd /workspace/test_downloads
Copia y pega el siguiente bloque de comandos en la terminal para descargar todas las dependencias a tu volumen de red:
code
Bash
# Descargar el archivo de recursos desde GitHub
wget https://raw.githubusercontent.com/ceutaseguridad/serverless-img/main/morpheus_resources_image.txt

# Leer el archivo y procesar para descargar todo
grep -v '^#' "morpheus_resources_image.txt" | while IFS=, read -r type name url; do
    type=$(echo "$type" | xargs); name=$(echo "$name" | xargs); url=$(echo "$url" | xargs)
    if [ -z "$type" ]; then continue; fi
    echo "--- Procesando: ${type} | ${name} ---"
    if [ "$type" == "GIT" ]; then
        git clone "${url}" "./${name}"
    elif [ "$type" == "URL_AUTH" ]; then
        folder=$(dirname "${name}"); mkdir -p "./${folder}"; wget -O "./${name}" "${url}"
    elif [ "$type" == "MODEL" ]; then
        IFS=, read -r _ folder hf_repo filename <<< "$type,$name,$url"
        folder=$(echo "$folder" | xargs); hf_repo=$(echo "$hf_repo" | xargs); filename=$(echo "$filename" | xargs)
        mkdir -p "./${folder}"; wget -O "./${folder}/${filename}" "https://huggingface.co/${hf_repo}/resolve/main/${filename}"
    fi
done
3. Verificar la Estructura de Archivos
Una vez finalizadas las descargas, ejecuta ls -R para listar todos los archivos y carpetas.
Confirma que la estructura de directorios (checkpoints/, ipadapter/, etc.) se ha creado correctamente dentro de /workspace/test_downloads.
Esta estructura valida que la lógica de rutas en el script pod_start.sh es correcta.
4. Limpieza
Una vez satisfecho con la verificación, puedes terminar y destruir el pod de prueba.
Los archivos descargados permanecerán en tu Network Volume, listos para ser usados como caché por el endpoint serverless, garantizando un primer arranque casi instantáneo.
