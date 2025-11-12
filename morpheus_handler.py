# morpheus_handler.py (Versión de Verificación de Archivo)

import runpod
import logging
import json
import os
import time

# --- Configuración del Logging ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# --- Copia y Carga del Handler Original de ComfyUI ---
if not os.path.exists("comfy_handler.py"):
    # Asegúrate de que el handler original se copia para poder llamarlo
    os.system("cp /handler.py ./comfy_handler.py")
import comfy_handler

# ---------------------------------------------------------------------------- #
#                          HANDLER DE VERIFICACIÓN                               #
# ---------------------------------------------------------------------------- #

def handler(job):
    """
    Este handler ejecuta el trabajo de ComfyUI y luego verifica si los
    archivos de salida se han creado en el almacenamiento persistente.
    """
    job_id = job.get('id', 'unknown_job_id')
    logging.info(f"--- Iniciando handler de verificación para el trabajo: {job_id} ---")

    # 1. DEFINIR LA RUTA DE SALIDA CORRECTA
    # Basado en la investigación, la ruta para Serverless es /runpod-volume
    # Se recomienda usar una subcarpeta por trabajo para mantener el orden.
    output_dir = f"/runpod-volume/job_outputs/{job_id}"
    logging.info(f"Directorio de salida esperado: {output_dir}")

    # Es buena práctica asegurarse de que el directorio base exista
    os.makedirs("/runpod-volume/job_outputs", exist_ok=True)

    comfyui_result = None
    comfyui_error = None

    # 2. EJECUTAR EL TRABAJO DE COMFYUI
    try:
        logging.info("Invocando a comfy_handler.handler...")
        # El handler de ComfyUI puede ser un generador, lo consumimos para completarlo
        result_generator = comfy_handler.handler(job)
        for result in result_generator:
            comfyui_result = result
        logging.info("La ejecución de comfy_handler.handler ha finalizado.")
    except Exception as e:
        logging.error(f"Se ha producido una excepción al ejecutar comfy_handler: {e}", exc_info=True)
        comfyui_error = str(e)

    # Pequeña pausa para asegurar la sincronización del sistema de archivos de red
    time.sleep(2)

    # 3. VERIFICAR EL SISTEMA DE ARCHIVOS
    logging.info(f"Verificando el sistema de archivos en '{output_dir}'...")
    directory_exists = os.path.exists(output_dir)
    files_in_directory = []
    if directory_exists:
        try:
            files_in_directory = os.listdir(output_dir)
        except OSError as e:
            logging.error(f"Error al leer el directorio {output_dir}: {e}")

    logging.info(f"Verificación completada. ¿Existe el directorio?: {directory_exists}. Archivos encontrados: {files_in_directory}")

    # 4. DEVOLVER UN INFORME DETALLADO
    return {
        "status": "verification_complete",
        "job_id": job_id,
        "checked_path": output_dir,
        "directory_exists": directory_exists,
        "files_found": files_in_directory,
        "comfyui_raw_output": comfyui_result,
        "comfyui_execution_error": comfyui_error
    }


if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
