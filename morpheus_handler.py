# morpheus_handler.py (Nuevo archivo)

import os
import json
import runpod
from runpod.serverless.utils.rp_validator import validate

# Importamos el handler original de la plantilla. 
# Asumimos que está en un archivo llamado 'comfy_handler.py' en la plantilla base.
# Si el nombre es diferente (ej. 'handler.py'), ajústalo aquí.
import comfy_handler 

# Definimos el esquema de validación para el input que esperamos
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
    Toma el input simple y lo convierte en el 'prompt' completo que ComfyUI entiende.
    Esta es la lógica que hemos movido desde el Orquestador local al microservicio.
    """
    workflow_name = job_input['workflow_name']
    params = job_input['params']

    # La plantilla de RunPod ComfyUI copia los workflows a /comfyui/workflows
    # Pero nuestro pod_start.sh los copia a /runpod-volume/morpheus_lib/workflows
    workflow_path = f"/runpod-volume/morpheus_lib/workflows/{workflow_name}.json"

    if not os.path.exists(workflow_path):
        raise FileNotFoundError(f"El archivo de workflow '{workflow_path}' no fue encontrado dentro del worker.")

    with open(workflow_path, 'r') as f:
        prompt_template = f.read()

    # Reemplazamos los placeholders
    final_workflow_str = prompt_template
    for key, value in params.items():
        placeholder = f'"__param:{key}__"'
        final_workflow_str = final_workflow_str.replace(placeholder, json.dumps(value))
    
    final_prompt = json.loads(final_workflow_str)
    return final_prompt

def morpheus_handler(job):
    """
    Este es nuestro handler personalizado. Valida, prepara y luego delega
    el trabajo al handler original de ComfyUI.
    """
    # 1. Validar el input que nos llega desde Morpheus
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
            "api_name": job_input['workflow_name'] # api_name puede ser opcional, pero lo mantenemos por si acaso
        }
    }

    # 4. Llamar al handler original de ComfyUI con el trabajo ya formateado
    return comfy_handler.handler(comfy_job)

# Iniciar el servidor de runpod con nuestro handler personalizado
runpod.serverless.start({"handler": morpheus_handler})
