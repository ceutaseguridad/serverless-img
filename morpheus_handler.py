# morpheus_handler.py (Versión 18 - Definitiva)

import os
import json
import runpod
from runpod.serverless.utils.rp_validator import validate
import comfy_handler 

INPUT_SCHEMA = {
    'workflow_name': { 'type': str, 'required': True },
    'params': { 'type': dict, 'required': True }
}

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

def _reformat_comfyui_output(comfy_output):
    if not isinstance(comfy_output, dict) or 'error' in comfy_output:
        return comfy_output
    for node_id, node_output in comfy_output.items():
        if 'images' in node_output:
            for image_data in node_output['images']:
                filename = image_data.get('filename')
                subfolder = image_data.get('subfolder')
                base_path = "/comfyui/output"
                full_path = os.path.join(base_path, subfolder, filename) if subfolder else os.path.join(base_path, filename)
                return { "image_pod_path": full_path }
    return {"error": "El workflow de ComfyUI no produjo ninguna imagen."}

def morpheus_handler(job):
    """
    Handler final: Valida, Prepara, Ejecuta y Traduce, respetando la estructura del job.
    """
    try:
        job_input = job.get('input')
        if not job_input:
            return {"error": "El objeto 'job' no contiene la clave 'input'."}
        
        validated_input = validate(job_input, INPUT_SCHEMA)
        if 'errors' in validated_input:
            return {"error": validated_input['errors']}
        
        final_prompt = _prepare_comfyui_prompt(validated_input['validated_input'])

        # --- [SOLUCIÓN DEFINITIVA] ---
        # Modificamos el objeto 'job' original para inyectar nuestro prompt preparado,
        # pero conservamos el resto de la estructura (como el 'id').
        job['input'] = { "prompt": final_prompt }
        
        # Ahora llamamos al handler original con el objeto 'job' completo y modificado.
        result_generator = comfy_handler.handler(job)
        # --- [FIN DE LA SOLUCIÓN] ---
        
        result_list = list(result_generator)
        if not result_list:
            return {"error": "El handler de ComfyUI no devolvió ningún resultado."}

        final_result = result_list[-1]
        return _reformat_comfyui_output(final_result)

    except Exception as e:
        # Devolvemos el error específico para una mejor depuración en la app local.
        return {"error": f"Error inesperado en morpheus_handler: {str(e)}"}

runpod.serverless.start({"handler": morpheus_handler})
