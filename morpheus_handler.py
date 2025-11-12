# morpheus_handler.py (Versión Verificada por el Señuelo)

import os
import json
import runpod
import logging

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
        if not all([job_id, job_input]):
            return {"error": "El objeto 'job' es inválido."}

        # LA VERDAD VERIFICADA: El worker ve el disco en /runpod-volume.
        base_persistent_path = "/runpod-volume"
        
        # --- 1. DEFINIR RUTAS PERSISTENTES ---
        output_dir = f"{base_persistent_path}/job_outputs/{job_id}"
        logging.info(f"Ruta de salida persistente: {output_dir}")
        os.makedirs(output_dir, exist_ok=True)
        
        workflow_name = "minimal_test"
        workflow_path = f"{base_persistent_path}/morpheus_lib/workflows/{workflow_name}.json"
        
        # --- 2. CARGAR Y PREPARAR WORKFLOW ---
        logging.info(f"Cargando workflow desde: {workflow_path}")
        if not os.path.exists(workflow_path):
            return {"error": f"Workflow '{workflow_path}' NO encontrado."}

        logging.info("Workflow encontrado. Reemplazando parámetros...")
        with open(workflow_path, 'r') as f:
            prompt_template = f.read()

        params = job_input.get('params', {})
        params['output_path'] = output_dir 
        
        final_workflow_str = prompt_template
        for key, value in params.items():
            final_workflow_str = final_workflow_str.replace(f'"__param:{key}__"', json.dumps(value))
        
        final_prompt = json.loads(final_workflow_str)

        # --- 3. CONSTRUIR Y LOGUEAR JOB PARA COMFY_HANDLER ---
        comfy_job = {"id": job_id, "input": { "prompt": final_prompt }}
        logging.info(f"Enviando a ComfyUI el siguiente prompt: {json.dumps(final_prompt, indent=2)}")
        logging.info("Invocando a comfy_handler...")
        
        # --- 4. EJECUTAR Y CAPTURAR RESULTADO ---
        comfy_output = None
        for result in comfy_handler.handler(comfy_job):
            logging.info(f"Recibido del generador de ComfyUI: {result}")
            comfy_output = result
        
        logging.info("Ejecución de comfy_handler finalizada.")

        if not isinstance(comfy_output, dict):
            return {"error": f"Error de ComfyUI (tipo de dato inesperado: {type(comfy_output)}), contenido: {comfy_output}"}

        # --- 5. BUSCAR Y VERIFICAR EL ARCHIVO DE SALIDA ---
        logging.info("Procesando output para encontrar imagen...")
        for node_id, node_data in comfy_output.items():
            if 'images' in node_data:
                for image_data in node_data['images']:
                    filename = image_data.get('filename')
                    if not filename: continue
                    
                    full_persistent_path = os.path.join(output_dir, filename)
                    logging.info(f"Imagen encontrada: '{filename}'. Verificando en: '{full_persistent_path}'")
                    
                    if os.path.exists(full_persistent_path):
                        logging.info("¡ÉXITO! Devolviendo ruta.")
                        return { "image_pod_path": full_persistent_path }
                    else:
                        return {"error": f"CRÍTICO: Archivo '{filename}' reportado pero NO encontrado."}

        return {"error": "Workflow completado, pero no se encontraron imágenes.", "raw_output": comfy_output}

    except Exception as e:
        logging.error(f"Error fatal en morpheus_handler: {str(e)}", exc_info=True)
        return {"error": f"Excepción fatal en morphema_handler: {str(e)}"}

if __name__ == "__main__":
    runpod.serverless.start({"handler": morpheus_handler})
