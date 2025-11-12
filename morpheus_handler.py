# morpheus_handler.py (Versión v25 - Final Logic)

import os
import json
import runpod
import logging
import glob
import time
import requests

logging.basicConfig(level=logging.INFO, format='%(asctime=s - %(levelname)s - %(message)s')

COMFYUI_URL = "http://127.0.0.1:8188/prompt"

def find_and_replace_placeholders(obj, params):
    """
    Recorre recursivamente un objeto (diccionario o lista) y reemplaza
    los placeholders del tipo '__param:key__' con los valores de 'params'.
    """
    if isinstance(obj, dict):
        return {k: find_and_replace_placeholders(v, params) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [find_and_replace_placeholders(elem, params) for elem in obj]
    elif isinstance(obj, str) and obj.startswith('__param:'):
        key = obj.split(':', 1)[1]
        return params.get(key, obj) # Devuelve el valor o el placeholder si no se encuentra
    else:
        return obj

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
            workflow_template = json.load(f) # Cargamos directamente como objeto Python

        # --- [INICIO DE LA CORRECCIÓN DEFINITIVA] ---
        # 1. Preparamos el diccionario de parámetros a reemplazar.
        params_to_replace = job_input.copy()
        params_to_replace['output_path'] = output_dir

        # 2. Usamos una función recursiva para reemplazar los placeholders
        #    en la estructura del workflow, manteniendo los tipos de datos.
        final_prompt = find_and_replace_placeholders(workflow_template, params_to_replace)
        
        # 3. El payload para la API es el workflow ya procesado.
        payload = {"prompt": final_prompt}
        # --- [FIN DE LA CORRECCIÓN] ---

        logging.info("Payload final construido. Estructura de nodos procesada.")
        # Opcional: Descomentar para ver el payload exacto que se envía
        # logging.debug(f"Payload a enviar a ComfyUI: {json.dumps(payload, indent=2)}")

        logging.info(f"Enviando petición POST a la API de ComfyUI en {COMFYUI_URL}")
        response = requests.post(COMFYUI_URL, json=payload)

        logging.info(f"Respuesta de la API de ComfyUI | Código de estado: {response.status_code}")
        
        if response.status_code == 200:
            logging.info("El trabajo fue ACEPTADO por ComfyUI. Procesando...")
            
            # El tiempo de espera puede ser crucial para trabajos largos y escrituras en red
            time.sleep(10) # Aumentamos el tiempo de espera por seguridad
            
            found_files = glob.glob(os.path.join(output_dir, '*.png'))
            
            if found_files:
                image_path = found_files[0]
                logging.info(f"¡ÉXITO! Archivo encontrado: {image_path}")
                return { "image_pod_path": image_path }
            else:
                logging.error("Error CRÍTICO: Trabajo aceptado, pero no se encontró el .png en la salida.")
                return {"error": "El trabajo fue aceptado pero el archivo de imagen no se encontró."}
        else:
            # Si el código no es 200, logueamos el cuerpo para el diagnóstico.
            logging.error(f"Respuesta de la API de ComfyUI | Cuerpo: {response.text}")
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
