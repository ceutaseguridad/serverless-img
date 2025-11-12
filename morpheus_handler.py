# morpheus_handler.py (Versión v33 - Stable Mapping)

import os
import json
import runpod
import logging
import glob
import time
import requests

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

COMFYUI_URL = "http://127.0.0.1:8188/prompt"
COMFYUI_OUTPUT_DIR = "/comfyui/output"

# El mapa de "traducción" es la forma correcta y robusta de manejar esto.
PARAM_MAP = {
    "cfg_scale": "cfg"
    # Añadir cualquier otra "traducción" necesaria en el futuro aquí.
}

def morpheus_handler(job):
    job_id = job.get('id', 'id_desconocido')
    logging.info(f"--- Inicio del trabajo: {job_id} ---")

    try:
        job_input = job.get('input')
        workflow_name = job_input.get('workflow_name')
        workflow_path = f"/runpod-volume/morpheus_lib/workflows/{workflow_name}.json"
        
        logging.info(f"Cargando plantilla de workflow desde: {workflow_path}")
        with open(workflow_path, 'r') as f:
            workflow_template_str = f.read()

        params_to_replace = job_input.copy()
        
        # Corrección del filename_prefix: Usamos el job_id para guardar en la carpeta de salida por defecto de ComfyUI.
        params_to_replace['filename_prefix'] = job_id

        final_workflow_str = workflow_template_str
        
        for key_from_ui, value in params_to_replace.items():
            # Usamos el mapa para obtener el nombre de placeholder correcto.
            key_for_workflow = PARAM_MAP.get(key_from_ui, key_from_ui)
            
            placeholder = f'"__param:{key_for_workflow}__"'
            
            if isinstance(value, str):
                replacement = json.dumps(value)
            else:
                replacement = str(value).lower()

            final_workflow_str = final_workflow_str.replace(placeholder, replacement)
        
        final_prompt = json.loads(final_workflow_str)
        payload = {"prompt": final_prompt}
        
        logging.info(f"Payload construido. Prefijo de salida: {job_id}")
        
        logging.info(f"Enviando petición POST a la API de ComfyUI en {COMFYUI_URL}")
        response = requests.post(COMFYUI_URL, json=payload)

        logging.info(f"Respuesta de la API de ComfyUI | Código de estado: {response.status_code}")
        
        if response.status_code == 200:
            logging.info("¡TRABAJO ACEPTADO! ComfyUI está procesando la imagen.")
            timeout_seconds = 180
            start_time = time.time()
            image_path = None
            
            while time.time() - start_time < timeout_seconds:
                # Buscamos en el directorio de salida de ComfyUI archivos que empiecen con nuestro job_id.
                found_files = glob.glob(os.path.join(COMFYUI_OUTPUT_DIR, f'{job_id}*.png'))
                if found_files:
                    image_path = found_files[0]
                    logging.info(f"¡ÉXITO! Archivo de salida encontrado: {image_path}")
                    break
                time.sleep(3)
            
            if image_path:
                return { "image_pod_path": image_path }
            else:
                logging.error(f"Error CRÍTICO: Timeout. No se encontró el .png después de {timeout_seconds} segundos.")
                return {"error": "Timeout: El archivo de imagen no se encontró a tiempo."}
        else:
            logging.error(f"Respuesta de la API de ComfyUI | Cuerpo: {response.text}")
            return { "error": "La API de ComfyUI rechazó el trabajo.", "status_code": response.status_code, "details": response.text }

    except Exception as e:
        logging.error(f"Error fatal en morpheus_handler: {str(e)}", exc_info=True)
        return {"error": f"Excepción fatal: {str(e)}"}

if __name__ == "__main__":
    runpod.serverless.start({"handler": morpheus_handler})
