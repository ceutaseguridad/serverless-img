# morpheus_handler.py (Versión v24 - Fixed)

import os
import json
import runpod
import logging
import glob
import time
import requests

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

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
        workflow_path = f"{base_persistent_path}/morpheus_lib/workflows/{workflow_name}.json"
        
        logging.info(f"Cargando workflow desde: {workflow_path}")
        with open(workflow_path, 'r') as f:
            prompt_template = f.read()

        # --- [INICIO DE LA CORRECCIÓN CRÍTICA] ---
        # El payload de 'tasks.py' es plano. 'job_input' contiene todos los parámetros.
        # Creamos un diccionario de parámetros para reemplazar a partir de 'job_input'.
        params_to_replace = job_input.copy()
        
        # Añadimos el output_path, que se genera aquí en el worker.
        params_to_replace['output_path'] = output_dir 
        # --- [FIN DE LA CORRECCIÓN] ---
        
        final_workflow_str = prompt_template
        for key, value in params_to_replace.items():
            # No intentamos reemplazar 'workflow_name' ya que no es un parámetro del JSON.
            if key == 'workflow_name':
                continue
            
            # La lógica de reemplazo es correcta, solo necesitaba los datos correctos.
            final_workflow_str = final_workflow_str.replace(f'"__param:{key}__"', json.dumps(value))
        
        final_prompt = json.loads(final_workflow_str)
        payload = {"prompt": final_prompt}
        
        logging.info(f"Enviando petición POST directa a la API de ComfyUI en {COMFYUI_URL}")
        response = requests.post(COMFYUI_URL, json=payload)

        logging.info(f"Respuesta de la API de ComfyUI | Código de estado: {response.status_code}")
        logging.info(f"Respuesta de la API de ComfyUI | Cuerpo: {response.text}")

        if response.status_code == 200:
            logging.info("El trabajo fue ACEPTADO por ComfyUI. Esperando la generación del archivo.")
            
            # Damos tiempo suficiente para que la imagen se escriba en el volumen de red.
            time.sleep(5)
            
            found_files = glob.glob(os.path.join(output_dir, '*.png'))
            
            if found_files:
                image_path = found_files[0]
                logging.info(f"¡ÉXITO! Archivo encontrado manualmente: {image_path}")
                # La salida DEBE coincidir con la que espera 'tasks.py'
                return { "image_pod_path": image_path }
            else:
                logging.error("Error CRÍTICO: ComfyUI aceptó el trabajo, pero no se encontró el .png en la salida.")
                return {"error": "El trabajo fue aceptado por la API pero no se encontró el archivo de imagen."}
        else:
            logging.error("Error CRÍTICO: El trabajo fue RECHAZADO por la API de ComfyUI.")
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
