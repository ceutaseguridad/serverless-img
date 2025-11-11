# morpheus_handler.py (Versión de Depuración de Output)

import os
import json
import runpod
from runpod.serverless.utils.rp_validator import validate
import comfy_handler 

# ... (INPUT_SCHEMA y _prepare_comfyui_prompt no cambian) ...
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
    # --- INICIO DE LA SECCIÓN DE DEBUG ---
    print("--- DENTRO DE _reformat_comfyui_output ---")
    print(f"DEBUG: Tipo de dato recibido: {type(comfy_output)}")
    try:
        # Intentamos imprimirlo como JSON para ver su estructura
        print(f"DEBUG: Contenido recibido (json):\n{json.dumps(comfy_output, indent=2)}")
    except Exception as e:
        # Si no es JSON, lo imprimimos como string
        print(f"DEBUG: Contenido recibido (no es JSON, como string): {comfy_output}")
    # --- FIN DE LA SECCIÓN DE DEBUG ---

    if not isinstance(comfy_output, dict) or 'error' in comfy_output:
        return comfy_output

    for node_id, node_output in comfy_output.items():
        if 'images' in node_output:
            for image_data in node_output['images']:
                filename = image_data.get('filename')
                subfolder = image_data.get('subfolder')
                base_path = "/comfyui/output"
                full_path = os.path.join(base_path, subfolder, filename) if subfolder else os.path.join(base_path, filename)
                
                final_output = {"image_pod_path": full_path}
                print(f"DEBUG: Output reformateado final: {final_output}")
                return final_output

    return {"error": "El workflow de ComfyUI no produjo ninguna imagen."}

def morpheus_handler(job):
    print("--- INICIO DE MORPHEUS_HANDLER ---")
    try:
        validated_input = validate(job['input'], INPUT_SCHEMA)
        if 'errors' in validated_input:
            return {"error": validated_input['errors']}
        job_input = validated_input['validated_input']
        print("DEBUG: Input validado correctamente.")

        final_prompt = _prepare_comfyui_prompt(job_input)
        print("DEBUG: Prompt de ComfyUI preparado.")

        comfy_job = { "input": { "prompt": final_prompt, "api_name": job_input['workflow_name'] } }

        print("DEBUG: Llamando a comfy_handler.handler...")
        result = comfy_handler.handler(comfy_job)
        print("DEBUG: comfy_handler.handler ha devuelto un resultado.")
        
        # El resultado se pasará a nuestra función de reformateo que ahora tiene prints
        return _reformat_comfyui_output(result)

    except Exception as e:
        print(f"ERROR FATAL en morpheus_handler: {e}")
        return {"error": f"Error inesperado en morpheus_handler: {str(e)}"}

print("--- MORPHEUS_HANDLER.PY CARGADO, INICIANDO SERVIDOR RUNPOD ---")
runpod.serverless.start({"handler": morpheus_handler})
