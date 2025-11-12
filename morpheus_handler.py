# morpheus_handler.py (Versión 22 - La Simple y Correcta)

import os
import json
import runpod
import comfy_handler 

def morpheus_handler(job):
    """
    Handler final que simplifica el flujo y se centra en la traducción.
    """
    try:
        job_id = job.get('id')
        job_input = job.get('input')
        if not all([job_id, job_input]):
            return {"error": "El objeto 'job' es inválido, no contiene 'id' o 'input'."}

        # --- 1. PREPARAR RUTA DE SALIDA PERSISTENTE ---
        # Como hemos verificado, el volumen persistente está en /workspace
        output_dir = f"/workspace/job_outputs/{job_id}"
        os.makedirs(output_dir, exist_ok=True)
        
        # --- 2. PREPARAR EL PROMPT CON LA RUTA DE SALIDA ---
        workflow_name = job_input.get('workflow_name')
        params = job_input.get('params', {})
        params['output_path'] = output_dir # Añadimos la ruta persistente
        
        workflow_path = f"/runpod-volume/morpheus_lib/workflows/{workflow_name}.json"
        if not os.path.exists(workflow_path):
            return {"error": f"Workflow '{workflow_path}' no encontrado."}

        with open(workflow_path, 'r') as f:
            prompt_template = f.read()

        final_workflow_str = prompt_template
        for key, value in params.items():
            placeholder = f'"__param:{key}__"'
            final_workflow_str = final_workflow_str.replace(placeholder, json.dumps(value))
        
        final_prompt = json.loads(final_workflow_str)

        # --- 3. CREAR UN NUEVO 'JOB' LIMPIO PARA COMFY_HANDLER ---
        # En lugar de modificar el 'job' original, creamos uno nuevo y limpio.
        # Le pasamos el 'id' porque hemos visto que lo necesita.
        comfy_job = {
            "id": job_id,
            "input": { "prompt": final_prompt }
        }
        
        # --- 4. EJECUTAR Y CAPTURAR EL RESULTADO ---
        comfy_output = None
        for result in comfy_handler.handler(comfy_job):
            # Asumimos que el último resultado es el bueno
            comfy_output = result
        
        if comfy_output is None:
            return {"error": "El handler de ComfyUI no produjo ningún output."}

        # Si el resultado es un string, es un error del handler interno.
        if isinstance(comfy_output, str):
            return {"error": f"Error interno del comfy_handler: {comfy_output}"}
        
        # Si no es un diccionario, es un tipo de error inesperado.
        if not isinstance(comfy_output, dict):
            return {"error": f"El comfy_handler devolvió un tipo de dato inesperado: {type(comfy_output)}"}

        # --- 5. DEVOLVER LA RUTA PERSISTENTE ---
        for node_id, node_data in comfy_output.items():
            if 'images' in node_data:
                for image_data in node_data['images']:
                    filename = image_data.get('filename')
                    full_persistent_path = os.path.join(output_dir, filename)
                    # Verificamos que el archivo realmente existe antes de devolverlo
                    if os.path.exists(full_persistent_path):
                        return { "image_pod_path": full_persistent_path }
                    else:
                        return {"error": f"El archivo '{filename}' no fue encontrado en la ruta de salida esperada."}

        return {"error": "Workflow completado pero no se encontraron imágenes en el output.", "raw_output": comfy_output}

    except Exception as e:
        return {"error": f"Error fatal en morpheus_handler: {str(e)}"}

runpod.serverless.start({"handler": morpheus_handler})
