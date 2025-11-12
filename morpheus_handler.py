import os
import json
import runpod
import logging

# --- Configuración del Logging ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# --- Importación Segura del Handler de ComfyUI ---
try:
    import comfy_handler 
except ImportError:
    logging.error("CRÍTICO: No se pudo importar 'comfy_handler'.")
    exit(1)

def morpheus_handler(job):
    """
    Handler que lee y escribe en las rutas PERSISTENTES correctas (/runpod-volume).
    """
    job_id = job.get('id', 'id_desconocido')
    logging.info(f"--- Inicio del trabajo: {job_id} ---")

    try:
        job_input = job.get('input')
        if not all([job_id, job_input]):
            error_msg = "El objeto 'job' es inválido."
            logging.error(error_msg)
            return {"error": error_msg}

        # --- 1. DEFINIR RUTAS PERSISTENTES ---
        output_dir = f"/runpod-volume/job_outputs/{job_id}"
        logging.info(f"Ruta de salida persistente: {output_dir}")
        os.makedirs(output_dir, exist_ok=True)
        
        workflow_name = job_input.get('workflow_name')
        workflow_path = f"/runpod-volume/morpheus_lib/workflows/{workflow_name}.json"
        
        # --- 2. CARGAR Y PREPARAR WORKFLOW ---
        logging.info(f"Intentando cargar el workflow desde: {workflow_path}")
        if not os.path.exists(workflow_path):
            error_msg = f"Workflow '{workflow_path}' NO encontrado."
            logging.error(error_msg)
            return {"error": error_msg}

        logging.info("Workflow encontrado. Reemplazando parámetros...")
        with open(workflow_path, 'r') as f:
            prompt_template = f.read()

        params = job_input.get('params', {})
        params['output_path'] = output_dir 
        
        final_workflow_str = prompt_template
        for key, value in params.items():
            placeholder = f'"__param:{key}__"'
            final_workflow_str = final_workflow_str.replace(placeholder, json.dumps(value))
        
        final_prompt = json.loads(final_workflow_str)

        # --- 3. CONSTRUIR JOB PARA COMFY_HANDLER ---
        comfy_job = {
            "id": job_id,
            "input": { "prompt": final_prompt }
        }

        # [CAMBIO CLAVE] Logueamos el prompt exacto que se va a enviar.
        logging.info(f"Enviando a ComfyUI el siguiente prompt: {json.dumps(final_prompt, indent=2)}")

        logging.info("'Job' para comfy_handler creado. Invocando...")
        
        # --- 4. EJECUTAR Y CAPTURAR RESULTADO ---
        comfy_output = None
        all_results = []
        result_generator = comfy_handler.handler(comfy_job)
        for result in result_generator:
            logging.info(f"Recibido resultado del generador de ComfyUI: {result}")
            all_results.append(result)
            comfy_output = result
        
        logging.info(f"Ejecución de comfy_handler finalizada. Total de resultados: {len(all_results)}.")

        if comfy_output is None:
            error_msg = "El handler de ComfyUI no produjo ningún output."
            logging.error(error_msg)
            return {"error": error_msg}

        if not isinstance(comfy_output, dict):
            error_msg = f"Error: comfy_handler devolvió un tipo de dato inesperado ({type(comfy_output)}), contenido: {comfy_output}"
            logging.error(error_msg)
            return {"error": error_msg}

        # --- 5. BUSCAR Y VERIFICAR EL ARCHIVO DE SALIDA ---
        logging.info("Procesando output final para encontrar la imagen...")
        for node_id, node_data in comfy_output.items():
            if 'images' in node_data:
                for image_data in node_data['images']:
                    filename = image_data.get('filename')
                    if not filename: continue
                    
                    full_persistent_path = os.path.join(output_dir, filename)
                    logging.info(f"Imagen encontrada: '{filename}'. Verificando en: '{full_persistent_path}'")
                    
                    if os.path.exists(full_persistent_path):
                        logging.info("¡ÉXITO! El archivo existe. Devolviendo ruta.")
                        return { "image_pod_path": full_persistent_path }
                    else:
                        error_msg = f"Error CRÍTICO: Archivo '{filename}' reportado pero NO encontrado."
                        logging.error(error_msg)
                        return {"error": error_msg}

        error_msg = "Workflow completado, pero no se encontraron imágenes."
        logging.warning(error_msg)
        return {"error": error_msg, "raw_output": comfy_output}

    except Exception as e:
        logging.error(f"Error fatal en morpheus_handler: {str(e)}", exc_info=True)
        return {"error": f"Excepción fatal en morpheus_handler: {str(e)}"}

if __name__ == "__main__":
    runpod.serverless.start({"handler": morpheus_handler})
