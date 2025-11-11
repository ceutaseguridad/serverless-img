# morpheus_handler.py (Versión Final)

import os
import json
import runpod
from runpod.serverless.utils.rp_validator import validate

# Importamos el handler original de la plantilla.
# Gracias a nuestro pod_start.sh, este archivo ya está en el mismo directorio.
import comfy_handler 

# Esquema de validación para el input
INPUT_SCHEMA = {
    'workflow_name': {
        'type': str,
        'required': True
    },
    'params': {
        'type': dict,
        'required': True
    }
}

def _prepare_comfyui_prompt(job_input):
    """
    Convierte nuestro input simple en el 'prompt' completo que ComfyUI entiende.
    """
    workflow_name = job_input['workflow_name']
    params = job_input['params']

    # La ruta a los workflows que copiamos en el pod_start.sh
    workflow_path = f"/runpod-volume/morpheus_lib/workflows/{workflow_name}.json"

    if not os.path.exists(workflow_path):
        raise FileNotFoundError(f"El archivo de workflow '{workflow_path}' no fue encontrado.")

    with open(workflow_path, 'r') as f:
        prompt_template = f.read()

    # Reemplazamos los placeholders __param:key__
    final_workflow_str = prompt_template
    for key, value in params.items():
        placeholder = f'"__param:{key}__"'
        final_workflow_str = final_workflow_str.replace(placeholder, json.dumps(value))
    
    final_prompt = json.loads(final_workflow_str)
    return final_prompt

# --- [INICIO DE LA CORRECCIÓN FINAL] FUNCIÓN PARA REFORMATEAR EL OUTPUT ---
def _reformat_comfyui_output(comfy_output):
    """
    Traduce el output estándar de ComfyUI al formato que nuestro orquestador espera.
    """
    if not isinstance(comfy_output, dict) or 'error' in comfy_output:
        return comfy_output # Si ya es un error, lo pasamos tal cual.

    # Buscamos la primera imagen en el output
    for node_id, node_output in comfy_output.items():
        if 'images' in node_output:
            for image_data in node_output['images']:
                filename = image_data.get('filename')
                subfolder = image_data.get('subfolder')
                
                # Construimos la ruta completa del archivo de salida
                base_path = "/comfyui/output"
                full_path = os.path.join(base_path, subfolder, filename) if subfolder else os.path.join(base_path, filename)

                # Creamos el nuevo diccionario de salida que nuestro tasks.py entiende
                # La clave 'image_pod_path' es un ejemplo, pero al terminar en '_pod_path' será reconocida.
                reformatted_output = {
                    "image_pod_path": full_path
                }
                return reformatted_output

    # Si no se encuentra ninguna imagen, devolvemos un error claro
    return {"error": "El workflow de ComfyUI se completó pero no se encontraron imágenes en el output."}
# --- [FIN DE LA CORRECCIÓN FINAL] ---


def morpheus_handler(job):
    """
    Nuestro handler personalizado: Valida, Prepara, Ejecuta y Reformatea.
    """
    # 1. Validar el input
    validated_input = validate(job['input'], INPUT_SCHEMA)
    if 'errors' in validated_input:
        return {"error": validated_input['errors']}
    
    job_input = validated_input['validated_input']

    # 2. Preparar el 'prompt' de ComfyUI
    try:
        final_prompt = _prepare_comfyui_prompt(job_input)
    except Exception as e:
        return {"error": f"Fallo al preparar el prompt de ComfyUI: {e}"}

    # 3. Construir el 'job' que el handler original de ComfyUI espera
    comfy_job = {
        "input": {
            "prompt": final_prompt,
            "api_name": job_input['workflow_name']
        }
    }

    # 4. Llamar al handler original de ComfyUI
    result = comfy_handler.handler(comfy_job)

    # 5. [PASO FINAL] Reformatear el resultado antes de devolverlo
    return _reformat_comfyui_output(result)

# Iniciar el servidor de runpod con nuestro handler personalizado
runpod.serverless.start({"handler": morpheus_handler})
