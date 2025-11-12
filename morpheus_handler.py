# morpheus_handler.py (V31 CON ARREGLO DE GUARDADO ÚNICAMENTE)

import os
import json
import runpod
import logging
import glob
import time
import requests

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

COMFYUI_URL = "http://127.0.0.1:8188/prompt"
# --- [INICIO] CAMBIO 1 DE 3 ---
COMFYUI_OUTPUT_DIR = "/comfyui/output"
# --- [FIN] CAMBIO 1 DE 3 ---

def morpheus_handler(job):
    job_id = job.get('id', 'id_desconocido')
    logging.info(f"--- Inicio del trabajo: {job_id} ---")

    try:
        job_input = job.get('input')
        base_persistent_path = "/runpod-volume"
        # Esta línea ya no es relevante para el guardado pero se deja
        output_dir = f"{base_persistent_path}/job_outputs/{job_id}"
        os.makedirs(output_dir, exist_ok=True)
        
        workflow_name = job_input.get('workflow_name')
        workflow_path = f"{base_persistent_path}/morpheus_lib/workflows/{workflow_name}.json"
        
        logging.info(f"Cargando plantilla de workflow desde: {workflow_path}")
        with open(workflow_path, 'r') as f:
            workflow_template_str = f.read()

        # Preparamos los parámetros para el reemplazo.
        params_to_replace = job_input.copy()
        
        # --- [INICIO] CAMBIO 2 DE 3 ---
        # El placeholder `__param:output_path__` recibe solo el job_id para que ComfyUI lo acepte.
        params_to_replace['output_path'] = job_id
        # --- [FIN] CAMBIO 2 DE 3 ---

        # ESTA ES LA LÓGICA ORIGINAL DE V31 QUE FUNCIONABA. NO SE TOCA.
        final_workflow_str = workflow_template_str
        for key, value in params_to_replace.items():
            placeholder = f'"__param:{key}__"'
            
            if isinstance(value, str):
                replacement = json.dumps(value)
            else:
                replacement = str(value).lower()

            final_workflow_str = final_workflow_str.replace(placeholder, replacement)
        
        final_prompt = json.loads(final_workflow_str)
        payload = {"prompt": final_prompt}
        
        logging.info("Payload construido mediante reemplazo de texto sobre plantilla JSON.")
        
        logging.info(f"Enviando petición POST a la API de ComfyUI en {COMFYUI_URL}")
        response = requests.post(COMFYUI_URL, json=payload)

        logging.info(f"Respuesta de la API de ComfyUI | Código de estado: {response.status_code}")
        
        if response.status_code == 200:
            logging.info("¡TRABAJO ACEPTADO! ComfyUI está procesando la imagen.")
            timeout_seconds = 180
            start_time = time.time()
            image_path = None
            
            # --- [INICIO] CAMBIO 3 DE 3 ---
            # Se busca el archivo en la carpeta correcta de ComfyUI
            while time.time() - start_time < timeout_seconds:
                found_files = glob.glob(os.path.join(COMFYUI_OUTPUT_DIR, f'{job_id}*.png'))
                if found_files:
                    image_path = found_files[0]
                    logging.info(f"¡ÉXITO! Archivo de salida encontrado: {image_path}")
                    break
                time.sleep(3)
            # --- [FIN] CAMBIO 3 DE 3 ---
            
            if image_path:
                return { "image_pod_path": image_path }
            else:
                logging.error(f"Error CRÍTICO: Timeout. No se encontró el .png después de {timeout_seconds} segundos.")
                return {"error": "Timeout: El archivo de imagen no se encontró a tiempo."}
        else:
            logging.error(f"Respuesta de la API de ComfyUI | Cuerpo: {response.text}")
            logging.error("Error CRÍTICO: La API de ComfyUI rechazó el trabajo.")
            return { "error": "La API de ComfyUI rechazó el trabajo.", "status_code": response.status_code, "details": response.text }

    except Exception as e:
        logging.error(f"Error fatal en morpheus_handler: {str(e)}", exc_info=True)
        return {"error": f"Excepción fatal: {str(e)}"}

if __name__ == "__main__":
    runpod.serverless.start({"handler": morpheus_handler})
