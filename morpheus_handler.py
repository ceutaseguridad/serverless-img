# morpheus_handler.py (Versión v27 - Mapping Adapter)

import os
import json
import runpod
import logging
import glob
import time
import requests

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

COMFYUI_URL = "http://127.0.0.1:8188/prompt"

# Diccionario para mapear los nombres de parámetros de la UI a los placeholders del workflow.
# Esto centraliza la lógica de "traducción" y hace el sistema más robusto.
PARAM_MAP = {
    "cfg_scale": "cfg",
    "output_path": "filename_prefix"
    # Añadir futuras traducciones aquí si es necesario.
}

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
        
        logging.info(f"Cargando plantilla de workflow desde: {workflow_path}")
        with open(workflow_path, 'r') as f:
            workflow_template_str = f.read()

        params_from_input = job_input.copy()
        params_from_input['output_path'] = output_dir

        final_workflow_str = workflow_template_str
        
        for key_from_ui, value in params_from_input.items():
            # Usamos el mapa para obtener el nombre correcto del placeholder.
            # Si la clave no está en el mapa, usamos la clave original.
            key_for_workflow = PARAM_MAP.get(key_from_ui, key_from_ui)
            
            placeholder = f'"__param:{key_for_workflow}__"'
            
            if isinstance(value, str):
                replacement = json.dumps(value)
            else:
                replacement = str(value).lower()

            final_workflow_str = final_workflow_str.replace(placeholder, replacement)
        
        final_prompt = json.loads(final_workflow_str)
        payload = {"prompt": final_prompt}

        logging.info("Payload final construido usando el mapa de parámetros.")
        # Descomenta para ver el JSON exacto que se envía a la API
        # logging.info(f"Payload a enviar: {json.dumps(payload, indent=2)}")

        logging.info(f"Enviando petición POST a la API de ComfyUI en {COMFYUI_URL}")
        response = requests.post(COMFYUI_URL, json=payload)

        logging.info(f"Respuesta de la API de ComfyUI | Código de estado: {response.status_code}")
        
        if response.status_code == 200:
            logging.info("¡TRABAJO ACEPTADO Y EN PROCESO POR COMFYUI!")
            
            # La ejecución real puede tardar. RunPod nos devolverá la respuesta cuando termine.
            # Aquí, simplemente esperamos a que el archivo aparezca.
            time.sleep(20) # Aumentamos el tiempo de espera para dar margen a la generación
            
            found_files = glob.glob(os.path.join(output_dir, '*.png'))
            
            if found_files:
                image_path = found_files[0]
                logging.info(f"¡ÉXITO! Archivo de salida encontrado: {image_path}")
                return { "image_pod_path": image_path }
            else:
                logging.error("Error CRÍTICO: El trabajo finalizó, pero no se encontró el archivo .png.")
                return {"error": "El trabajo fue aceptado pero el archivo de imagen no se encontró."}
        else:
            logging.error(f"Respuesta de la API de ComfyUI | Cuerpo: {response.text}")
            logging.error("Error CRÍTICO: La API de ComfyUI rechazó el trabajo.")
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
