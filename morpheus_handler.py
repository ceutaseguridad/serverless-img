# morpheus_handler.py (Versión v23 - Diagnostic)

import os
import json
import runpod
import logging
import glob
import time
import requests # Importamos la librería para hacer peticiones HTTP

# --- Configuración del Logging ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Constantes ---
# URL local del servidor ComfyUI que se ejecuta dentro del mismo pod
COMFYUI_URL = "http://127.0.0.1:8188/prompt"

def morpheus_handler(job):
    job_id = job.get('id', 'id_desconocido')
    logging.info(f"--- Inicio del trabajo: {job_id} ---")

    try:
        job_input = job.get('input')
        base_persistent_path = "/runpod-volume"
        output_dir = f"{base_persistent_path}/job_outputs/{job_id}"
        os.makedirs(output_dir, exist_ok=True)
        
        workflow_name = job_input.get('workflow_name')
        # La ruta debe usar /runpod-volume, que es el punto de montaje en el worker serverless
        workflow_path = f"{base_persistent_path}/morpheus_lib/workflows/{workflow_name}.json"
        
        logging.info(f"Cargando workflow desde: {workflow_path}")
        with open(workflow_path, 'r') as f:
            prompt_template = f.read()

        params = job_input.get('params', {})
        params['output_path'] = output_dir 
        
        # Reemplazamos los parámetros en la plantilla del workflow
        final_workflow_str = prompt_template
        for key, value in params.items():
            final_workflow_str = final_workflow_str.replace(f'"__param:{key}__"', json.dumps(value))
        
        # El workflow final que se enviará a la API de ComfyUI
        final_prompt = json.loads(final_workflow_str)
        
        # Preparamos el payload para la petición POST a la API de ComfyUI
        payload = {"prompt": final_prompt}
        
        logging.info(f"Enviando petición POST directa a la API de ComfyUI en {COMFYUI_URL}")
        
        # Realizamos la llamada directa a la API
        response = requests.post(COMFYUI_URL, json=payload)

        # --- ANÁLISIS DE LA RESPUESTA DIRECTA DE COMFYUI ---
        logging.info(f"Respuesta de la API de ComfyUI | Código de estado: {response.status_code}")
        logging.info(f"Respuesta de la API de ComfyUI | Cuerpo: {response.text}")

        if response.status_code == 200:
            logging.info("El trabajo fue ACEPTADO por ComfyUI. Esperando la generación del archivo.")
            
            # Damos un par de segundos para que el sistema de archivos de red se sincronice.
            time.sleep(3)
            
            found_files = glob.glob(os.path.join(output_dir, '*.png'))
            
            if found_files:
                image_path = found_files[0]
                logging.info(f"¡ÉXITO! Archivo encontrado manualmente: {image_path}")
                return { "image_pod_path": image_path }
            else:
                logging.error("Error CRÍTICO: ComfyUI aceptó el trabajo, pero no se encontró el .png en la salida.")
                return {"error": "El trabajo fue aceptado por la API pero no se encontró el archivo de imagen."}
        else:
            logging.error("Error CRÍTICO: El trabajo fue RECHAZADO por la API de ComfyUI.")
            # Devolvemos el error exacto que nos dio la API
            return {
                "error": "La API de ComfyUI rechazó el trabajo.",
                "status_code": response.status_code,
                "details": response.text
            }

    except Exception as e:
        logging.error(f"Error fatal en morpheus_handler: {str(e)}", exc_info=True)
        return {"error": f"Excepción fatal: {str(e)}"}

if __name__ == "__main__":
    runpod.serverless.start({"handler": morpheus_handler})
