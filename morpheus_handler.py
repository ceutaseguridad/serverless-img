# morpheus_handler.py (Versión Final con Traducción de Output)

import os
import json
import runpod
from runpod.serverless.utils.rp_validator import validate

# Este import funciona gracias a que pod_start.sh copia el archivo
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
    """
    Traduce el output estándar de ComfyUI al formato que nuestro orquestador espera.
    """
    if not isinstance(comfy_output, dict) or 'error' in comfy_output:
        return comfy_output

    # Busca en la salida la primera imagen generada
    for node_id, node_output in comfy_output.items():
        if 'images' in node_output:
            for image_data in node_output['images']:
                filename = image_data.get('filename')
                subfolder = image_data.get('subfolder')
                
                # Construye la ruta absoluta del archivo de salida dentro del worker
                base_path = "/comfyui/output"
                full_path = os.path.join(base_path, subfolder, filename) if subfolder else os.path.join(base_path, filename)

                # Devuelve el diccionario simple que tasks.py está esperando
                return {
                    "image_pod_path": full_path
                }

    # Si el bucle termina sin encontrar imágenes, devuelve un error claro
    return {"error": "El workflow de ComfyUI no produjo ninguna imagen."}

def morpheus_handler(job):
    """
    Nuestro handler personalizado: Valida, Prepara, Ejecuta y Traduce.
    """
    try:
        # 1. Validar
        validated_input = validate(job['input'], INPUT_SCHEMA)
        if 'errors' in validated_input:
            return {"error": validated_input['errors']}
        job_input = validated_input['validated_input']

        # 2. Preparar
        final_prompt = _prepare_comfyui_prompt(job_input)

        # 3. Construir trabajo para el handler original
        comfy_job = { "input": { "prompt": final_prompt, "api_name": job_input['workflow_name'] } }

        # 4. Ejecutar
        result = comfy_handler.handler(comfy_job)

        # 5. Traducir y Devolver
        return _reformat_comfyui_output(result)

    except Exception as e:
        return {"error": f"Error inesperado en morpheus_handler: {str(e)}"}

# Iniciar el servidor
runpod.serverless.start({"handler": morpheus_handler})
