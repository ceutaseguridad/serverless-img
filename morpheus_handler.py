import os
import json
import runpod
import comfy_handler 

def morpheus_handler(job):
    """
    Handler final con la ruta de montaje del volumen de red corregida.
    """
    try:
        job_id = job.get('id')
        job_input = job.get('input')
        if not all([job_id, job_input]):
            return {"error": "El objeto 'job' es inválido, no contiene 'id' o 'input'."}

        # --- [SOLUCIÓN DEFINITIVA] CORRECCIÓN DE LA RUTA BASE ---
        # La evidencia demuestra que el volumen de red está montado en /workspace.
        PERSISTENT_VOLUME_PATH = "/workspace"
        
        # 1. Preparar ruta de salida persistente
        output_dir = f"{PERSISTENT_VOLUME_PATH}/job_outputs/{job_id}"
        os.makedirs(output_dir, exist_ok=True)

        # 2. Preparar el prompt con la nueva ruta
        workflow_name = job_input.get('workflow_name')
        params = job_input.get('params', {})
        params['output_path'] = output_dir
        
        # Los workflows, sin embargo, los copiamos a /runpod-volume, así que esa ruta puede ser diferente.
        # Para ser consistentes, asumiremos que los workflows también están en una ruta relativa al montaje.
        # Si esto falla, sabemos que el error está aquí. Por ahora, asumimos que pod_start.sh los copia
        # a una subcarpeta del volumen persistente.
        # Basado en el script, la ruta es: /runpod-volume/morpheus_lib/workflows
        # Y si el volumen está en /workspace, entonces sería:
        workflow_path = f"/runpod-volume/morpheus_lib/workflows/{workflow_name}.json" 
        # Esta ruta la mantenemos porque es donde pod_start.sh copia los workflows,
        # incluso si la raíz del volumen es /workspace. Es confuso pero consistente con el script.
        
        if not os.path.exists(workflow_path):
            # Fallback por si la lógica anterior es incorrecta.
            workflow_path_alt = f"{PERSISTENT_VOLUME_PATH}/morpheus_lib/workflows/{workflow_name}.json"
            if not os.path.exists(workflow_path_alt):
                 return {"error": f"Workflow no encontrado ni en {workflow_path} ni en {workflow_path_alt}"}
            workflow_path = workflow_path_alt

        with open(workflow_path, 'r') as f:
            prompt_template = f.read()

        final_workflow_str = prompt_template
        for key, value in params.items():
            placeholder = f'"__param:{key}__"'
            final_workflow_str = final_workflow_str.replace(placeholder, json.dumps(value))
        
        final_prompt = json.loads(final_workflow_str)

        # 3. Ejecutar el trabajo
        job['input'] = { "prompt": final_prompt }
        
        comfy_output = None
        for result in comfy_handler.handler(job):
            comfy_output = result
        
        if comfy_output is None:
            return {"error": "El handler de ComfyUI no produjo ningún output."}

        # 4. Devolver la ruta persistente correcta
        for node_id, node_data in comfy_output.items():
            if 'images' in node_data:
                for image_data in node_data['images']:
                    filename = image_data.get('filename')
                    full_persistent_path = os.path.join(output_dir, filename)
                    return { "image_pod_path": full_persistent_path }

        return {"error": "Workflow completado pero no se encontraron imágenes.", "raw_output": comfy_output}

    except Exception as e:
        return {"error": f"Error inesperado en morpheus_handler: {str(e)}"}

runpod.serverless.start({"handler": morpheus_handler})
