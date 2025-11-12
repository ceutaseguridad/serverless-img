import os
import json
import runpod
import comfy_handler 

def morpheus_handler(job):
    """
    Handler final que guarda los resultados en el volumen persistente.
    """
    try:
        job_id = job.get('id')
        job_input = job.get('input')
        if not all([job_id, job_input]):
            return {"error": "El objeto 'job' es inválido, no contiene 'id' o 'input'."}

        # --- 1. PREPARAR RUTA DE SALIDA PERSISTENTE ---
        # Creamos un directorio único para este trabajo en el volumen de red.
        output_dir = f"/runpod-volume/job_outputs/{job_id}"
        os.makedirs(output_dir, exist_ok=True)

        # --- 2. PREPARAR EL PROMPT CON LA NUEVA RUTA ---
        workflow_name = job_input.get('workflow_name')
        params = job_input.get('params', {})
        
        # Añadimos nuestra ruta de salida persistente a los parámetros del workflow
        params['output_path'] = output_dir
        
        workflow_path = f"/runpod-volume/morpheus_lib/workflows/{workflow_name}.json"
        if not os.path.exists(workflow_path):
            raise FileNotFoundError(f"Workflow '{workflow_path}' no encontrado.")

        with open(workflow_path, 'r') as f:
            prompt_template = f.read()

        final_workflow_str = prompt_template
        for key, value in params.items():
            placeholder = f'"__param:{key}__"'
            final_workflow_str = final_workflow_str.replace(placeholder, json.dumps(value))
        
        final_prompt = json.loads(final_workflow_str)

        # --- 3. EJECUTAR EL TRABAJO ---
        job['input'] = { "prompt": final_prompt }
        
        comfy_output = None
        for result in comfy_handler.handler(job):
            comfy_output = result
        
        if comfy_output is None:
            return {"error": "El handler de ComfyUI no produjo ningún output."}

        # --- 4. DEVOLVER LA RUTA PERSISTENTE ---
        # Ahora que el archivo está en una ruta predecible, podemos construirla.
        # El output de ComfyUI nos da el nombre del archivo.
        for node_id, node_data in comfy_output.items():
            if 'images' in node_data:
                for image_data in node_data['images']:
                    filename = image_data.get('filename')
                    # La ruta completa ahora está en nuestro directorio de salida persistente.
                    full_persistent_path = os.path.join(output_dir, filename)
                    
                    return { "image_pod_path": full_persistent_path }

        return {"error": "Workflow completado pero no se encontraron imágenes en el output.", "raw_output": comfy_output}

    except Exception as e:
        return {"error": f"Error inesperado en morpheus_handler: {str(e)}"}

runpod.serverless.start({"handler": morpheus_handler})
