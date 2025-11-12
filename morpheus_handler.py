# morpheus_handler.py (v21 - Auditoría Profunda)
import os
import json
import shutil
import logging
import traceback
import runpod
from runpod.serverless.utils.rp_validator import validate
import comfy_handler 

# --- Configuración ---
INPUT_SCHEMA = {
    'workflow_name': { 'type': str, 'required': True },
    'params': { 'type': dict, 'required': True }
}
PERSISTENT_VOLUME_PATH = "/runpod-volume/morpheus_storage/outputs"
COMFYUI_TEMP_OUTPUT_PATH = "/workspace/ComfyUI/output"
DEBUG_LOG_PATH = "/runpod-volume/morpheus_storage/temp" # Directorio para logs de debug

# --- Configuración del Logging ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# --- Funciones de Ayuda ---
# _prepare_comfy_prompt y _process_and_move_output no cambian.
def _prepare_comfyui_prompt(job_input):
    workflow_name = job_input['workflow_name']
    params = job_input['params']
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
    logging.info(f"Procesando salida para el trabajo: {job_id}")
    if not isinstance(comfy_output, dict) or 'error' in comfy_output:
        return comfy_output
    for node_id, node_output in comfy_output.items():
        if 'images' in node_output:
            image_data = node_output['images'][0]
            original_filename = image_data.get('filename')
            temp_source_path = os.path.join(COMFYUI_TEMP_OUTPUT_PATH, original_filename)
            if not os.path.exists(temp_source_path):
                raise FileNotFoundError(f"El archivo de salida '{original_filename}' no se encontró en la ruta temporal '{temp_source_path}'.")
            job_persistent_dir = os.path.join(PERSISTENT_VOLUME_PATH, job_id)
            os.makedirs(job_persistent_dir, exist_ok=True)
            final_persistent_path = os.path.join(job_persistent_dir, original_filename)
            logging.info(f"Moviendo archivo: '{temp_source_path}' -> '{final_persistent_path}'")
            shutil.move(temp_source_path, final_persistent_path)
            relative_output_path = os.path.join("outputs", job_id, original_filename)
            final_output = {"image_pod_path": relative_output_path}
            logging.info(f"Proceso de salida finalizado. Devolviendo: {final_output}")
            return final_output
    return {"error": "El workflow de ComfyUI no produjo ninguna imagen."}

# --- Handler Principal ---

def morpheus_handler(job):
    job_id = job.get('id', 'unknown_job')
    logging.info(f"--- INICIO DE MORPHEUS_HANDLER (v21 - Auditoría) para el trabajo: {job_id} ---")
    try:
        validated_input = validate(job['input'], INPUT_SCHEMA)
        if 'errors' in validated_input:
            return {"error": validated_input['errors']}
        job_input = validated_input['validated_input']
        
        final_prompt = _prepare_comfyui_prompt(job_input)
        
        # --- [AUDITORÍA 1: Guardar el prompt final] ---
        os.makedirs(DEBUG_LOG_PATH, exist_ok=True)
        debug_prompt_file = os.path.join(DEBUG_LOG_PATH, f"{job_id}_prompt.json")
        with open(debug_prompt_file, 'w') as f:
            json.dump(final_prompt, f, indent=2)
        logging.info(f"Prompt final guardado para auditoría en: {debug_prompt_file}")
        # --- [FIN AUDITORÍA 1] ---
        
        job['input']['prompt'] = final_prompt
        
        final_comfy_result = None
        try:
            # --- [AUDITORÍA 2: Iterar y registrar el generador] ---
            logging.info("Iniciando iteración sobre el generador de comfy_handler...")
            result_generator = comfy_handler.handler(job)
            for i, result in enumerate(result_generator):
                logging.info(f"Resultado del generador (índice {i}): {result}")
                final_comfy_result = result # Guardamos el último resultado
            logging.info("Iteración sobre el generador completada.")
            # --- [FIN AUDITORÍA 2] ---
        except Exception as e:
            # --- [AUDITORÍA 3: Capturar excepciones explícitas] ---
            logging.error(f"¡EXCEPCIÓN CAPTURADA durante la ejecución de comfy_handler!")
            logging.error(traceback.format_exc())
            return {"error": f"Excepción en comfy_handler: {str(e)}"}
            # --- [FIN AUDITORÍA 3] ---

        if final_comfy_result is None:
            return {"error": "El handler de ComfyUI no devolvió ningún resultado."}
        
        logging.info(f"Salida CRUDA final recibida de comfy_handler: {final_comfy_result}")
        return _process_and_move_output(final_comfy_result, job_id)

    except Exception as e:
        logging.error(f"ERROR FATAL en la capa externa de morpheus_handler para el trabajo {job_id}: {e}", exc_info=True)
        return {"error": f"Error inesperado en morpheus_handler: {str(e)}"}

# --- Punto de Entrada de RunPod ---
logging.info("--- MORPHEUS_HANDLER.PY (v21 - Auditoría) CARGADO, INICIANDO SERVIDOR RUNPOD ---")
runpod.serverless.start({"handler": morpheus_handler})
