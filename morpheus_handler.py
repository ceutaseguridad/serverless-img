# morpheus_handler.py (Versión FINAL v22 - Ignorando el bug de comunicación)

import os
import json
import runpod
import logging
import glob
import time

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

try:
    import comfy_handler 
except ImportError:
    logging.error("CRÍTICO: No se pudo importar 'comfy_handler'.")
    exit(1)

def morpheus_handler(job):
    job_id = job.get('id', 'id_desconocido')
    logging.info(f"--- Inicio del trabajo: {job_id} ---")

    try:
        job_input = job.get('input')
        base_persistent_path = "/runpod-volume"
        output_dir = f"{base_persistent_path}/job_outputs/{job_id}"
        os.makedirs(output_dir, exist_ok=True)
        
        # Restauramos la lógica original para usar el workflow solicitado.
        workflow_name = job_input.get('workflow_name')
        workflow_path = f"{base_persistent_path}/morpheus_lib/workflows/{workflow_name}.json"
        
        logging.info(f"Cargando workflow: {workflow_path}")
        with open(workflow_path, 'r') as f:
            prompt_template = f.read()

        params = job_input.get('params', {})
        params['output_path'] = output_dir 
        
        final_workflow_str = prompt_template
        for key, value in params.items():
            final_workflow_str = final_workflow_str.replace(f'"__param:{key}__"', json.dumps(value))
        
        final_prompt = json.loads(final_workflow_str)
        comfy_job = {"id": job_id, "input": { "prompt": final_prompt }}

        logging.info("Invocando a comfy_handler. El resultado se ignorará.")
        
        # --- EJECUCIÓN A CIEGAS ---
        # Ejecutamos el generador para que haga su trabajo, sin esperar un resultado fiable.
        for result in comfy_handler.handler(comfy_job):
            logging.info(f"Comfy handler yield: {result}") # Logueamos lo que sea que devuelva, por si acaso

        logging.info("Ejecución finalizada. Buscando archivo de salida manualmente.")

        # --- BÚSQUEDA MANUAL DEL RESULTADO ---
        # Damos un par de segundos para que el sistema de archivos de red se sincronice.
        time.sleep(2)
        
        found_files = glob.glob(os.path.join(output_dir, '*.png'))
        
        if found_files:
            image_path = found_files[0]
            logging.info(f"¡ÉXITO! Archivo encontrado manualmente: {image_path}")
            return { "image_pod_path": image_path }
        else:
            logging.error("Error CRÍTICO: El trabajo finalizó pero no se encontró ningún .png en la salida.")
            return {"error": "El trabajo se ejecutó pero no se encontró el archivo de imagen."}

    except Exception as e:
        logging.error(f"Error fatal en morpheus_handler: {str(e)}", exc_info=True)
        return {"error": f"Excepción fatal: {str(e)}"}

if __name__ == "__main__":
    runpod.serverless.start({"handler": morpheus_handler})
