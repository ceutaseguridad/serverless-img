# Guía de Despliegue del Microservicio de Imágenes en RunPod

Este documento detalla el proceso paso a paso para desplegar el microservicio de imágenes de Morpheus AI Suite como un Endpoint Serverless en la plataforma RunPod.

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

## Proceso de Despliegue

Sigue estos pasos en la interfaz de usuario de RunPod:

### 1. Navegar a la Sección Serverless
- En el panel de la izquierda, haz clic en **Serverless**.
- En la página de `Endpoints`, haz clic en el botón **+ New Endpoint**.

### 2. Seleccionar la Plantilla
- Busca en la lista de plantillas y selecciona **`RunPod ComfyUI`**.

### 3. Elegir una GPU
- Se recomienda una GPU potente para un buen rendimiento. Una **NVIDIA GeForce RTX 4090** es una excelente opción.

### 4. Configurar los Workers
- **Max Workers:** `5` (o un número adecuado a la carga esperada).
- **Min Workers:** `0`. **¡Este es el paso más importante para la eficiencia de costes!** El servicio escalará a cero cuando esté inactivo.
- **Idle Timeout:** `5` (minutos). Un worker se apagará automáticamente tras 5 minutos de inactividad.

### 5. Establecer el Comando de Inicio del Contenedor
- Este comando clona este repositorio de configuración y ejecuta el script de arranque para instalar todas las dependencias.
- Copia y pega el siguiente comando **exactamente como está** en el campo `Container Start Command`:

```bash
git clone https://github.com/ceutaseguridad/serverless-img /workspace/morpheus_config && cd /workspace/morpheus_config && chmod +x pod_start.sh && ./pod_start.sh
