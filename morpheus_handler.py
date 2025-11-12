# morpheus_handler.py (v17 - Persistent Storage Integration)
import os
import json
import shutil
import logging
import runpod
from runpod.serverless.utils.rp_validator import validate
import comfy_handler 

# --- Configuración ---
INPUT_SCHEMA = {
    'workflow_name': { 'type': str, 'required': True },
    'params': { 'type': dict, 'required': True }
}
PERSISTENT_VOLUME_PATH = "/runpod-volume/morpheus_storage/outputs"
COMFYUI_TEMP_OUTPUT_PATH = "/workspace/ComfyUI/output" # Ruta de salida estándar en la plantilla de RunPod

# --- Configuración del Logging ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Funciones de Ayuda ---

def _prepare_comfyui_prompt(job_input):
    """Prepara el prompt de ComfyUI reemplazando placeholders en un archivo de workflow."""
    workflow_name = job_input['workflow_name']
    params = job_input['params']
    
    # [NOTA IMPORTANTE] Esta ruta asume que los workflows están en el volumen persistente.
    workflow_path = f"/runpod-volume/morpheus_lib/workflows/{workflow_name}.json"
    
    if not os.path.exists(workflow_path):
        raise FileNotFoundError(f"Workflow '{workflow_path}' no encontrado.")
    with open(workflow_path, 'r') as f:
        prompt_template = f.read()
    
    final_workflow_str = prompt_template
    for key, value in params.items():
        placeholder = f'"__param:{key}__"'
        final_workflow_str = final_workflow_str.replace(placeholder, json.dumps(value))
        
    return json.loads(final_workflow_str)

def _process_and_move_output(comfy_output, job_id):
    """
    [MODIFICADO] Procesa la salida de ComfyUI, mueve el archivo resultante al 
    almacenamiento persistente y devuelve la ruta relativa.
    """
    logging.info(f"Procesando salida para el trabajo: {job_id}")
    if not isinstance(comfy_output, dict) or 'error' in comfy_output:
        return comfy_output # Devuelve el error si ComfyUI falló

    for node_id, node_output in comfy_output.items():
        if 'images' in node_output:
            # Asumimos que solo nos interesa la primera imagen generada
            image_data = node_output['images'][0]
            original_filename = image_data.get('filename')
            
            # 1. Construir la ruta de origen (donde ComfyUI guardó el archivo temporalmente)
            temp_source_path = os.path.join(COMFYUI_TEMP_OUTPUT_PATH, original_filename)
            if not os.path.exists(temp_source_path):
                raise FileNotFoundError(f"El archivo de salida '{original_filename}' no se encontró en la ruta temporal '{temp_source_path}'.")

            # 2. Construir la ruta de destino en el almacenamiento persistente
            job_persistent_dir = os.path.join(PERSISTENT_VOLUME_PATH, job_id)
            os.makedirs(job_persistent_dir, exist_ok=True)
            final_persistent_path = os.path.join(job_persistent_dir, original_filename)

            # 3. Mover el archivo
            logging.info(f"Moviendo archivo: '{temp_source_path}' -> '{final_persistent_path}'")
            shutil.move(temp_source_path, final_persistent_path)

            # 4. Construir y devolver la ruta relativa que el cliente local necesita
            relative_output_path = os.path.join("outputs", job_id, original_filename)
            final_output = {"image_pod_path": relative_output_path}
            
            logging.info(f"Proceso de salida finalizado. Devolviendo: {final_output}")
            return final_output

    return {"error": "El workflow de ComfyUI no produjo ninguna imagen."}


# --- Handler Principal ---

def morpheus_handler(job):
    """Handler principal que orquesta el trabajo."""
    job_id = job.get('id', 'unknown_job')
    logging.info(f"--- INICIO DE MORPHEUS_HANDLER (v17) para el trabajo: {job_id} ---")
    try:
        validated_input = validate(job['input'], INPUT_SCHEMA)
        if 'errors' in validated_input:
            return {"error": validated_input['errors']}
        job_input = validated_input['validated_input']
        
        final_prompt = _prepare_comfyui_prompt(job_input)
        comfy_job = { "input": { "prompt": final_prompt } }

        # Consumir el generador de comfy_handler para obtener la lista de resultados
        result_generator = comfy_handler.handler(comfy_job)
        result_list = list(result_generator)
        
        if not result_list:
            return {"error": "El handler de ComfyUI no devolvió ningún resultado."}

        # El resultado final es el último elemento devuelto por el generador
        final_comfy_result = result_list[-1]
        
        # [MODIFICADO] Llamar a la nueva función que procesa y mueve el archivo
        return _process_and_move_output(final_comfy_result, job_id)

    except Exception as e:
        logging.error(f"ERROR FATAL en morpheus_handler para el trabajo {job_id}: {e}", exc_info=True)
        return {"error": f"Error inesperado en morpheus_handler: {str(e)}"}

# --- Punto de Entrada de RunPod ---
logging.info("--- MORPHEUS_HANDLER.PY (v17) CARGADO, INICIANDO SERVIDOR RUNPOD ---")
runpod.serverless.start({"handler": morpheus_handler})
