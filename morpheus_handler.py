# morpheus_handler.py (Versión 23 - Diagnóstico y Lógica Combinada)

import os
import json
import runpod
import logging

# --- Configuración del Logging (CRÍTICO PARA LA DEPURACIÓN) ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# --- Copia y Carga del Handler Original de ComfyUI ---
# Esta es una buena práctica para asegurar que la importación funciona
if not os.path.exists("comfy_handler.py"):
    logging.info("Copiando /handler.py a ./comfy_handler.py")
    os.system("cp /handler.py ./comfy_handler.py")
import comfy_handler 

def morpheus_handler(job):
    """
    Handler que combina la lógica final con un logging exhaustivo para depuración.
    """
    job_id = job.get('id', 'id_desconocido')
    logging.info(f"--- Inicio del trabajo: {job_id} ---")

    try:
        job_input = job.get('input')
        if not all([job_id, job_input]):
            error_msg = "El objeto 'job' es inválido, no contiene 'id' o 'input'."
            logging.error(error_msg)
            return {"error": error_msg}

        # --- 1. PREPARAR RUTA DE SALIDA PERSISTENTE ---
        # Corregido a /workspace basado en la evidencia del `ls`
        output_dir = f"/workspace/job_outputs/{job_id}"
        logging.info(f"Ruta de salida persistente definida como: {output_dir}")
        os.makedirs(output_dir, exist_ok=True)
        
        # --- 2. PREPARAR EL PROMPT CON LA RUTA DE SALIDA ---
        workflow_name = job_input.get('workflow_name')
        params = job_input.get('params', {})
        params['output_path'] = output_dir # Añadimos la ruta persistente
        
        # ¡ATENCIÓN! Si el volumen está en /workspace, esta ruta también debería estarlo.
        # Cambia "/runpod-volume/" por "/workspace/" si tus workflows están en el volumen.
        workflow_path = f"/workspace/morpheus_lib/workflows/{workflow_name}.json"
        logging.info(f"Intentando cargar el workflow desde: {workflow_path}")

        if not os.path.exists(workflow_path):
            error_msg = f"Workflow '{workflow_path}' NO encontrado. Verifica la ruta."
            logging.error(error_msg)
            return {"error": error_msg}

        logging.info("Workflow encontrado. Cargando y reemplazando parámetros...")
        with open(workflow_path, 'r') as f:
            prompt_template = f.read()

        final_workflow_str = prompt_template
        for key, value in params.items():
            placeholder = f'"__param:{key}__"'
            # El uso de json.dumps es correcto para manejar tipos de datos
            final_workflow_str = final_workflow_str.replace(placeholder, json.dumps(value))
        
        final_prompt = json.loads(final_workflow_str)

        # --- 3. CREAR UN NUEVO 'JOB' LIMPIO PARA COMFY_HANDLER ---
        comfy_job = {
            "id": job_id,
            "input": { "prompt": final_prompt }
        }
        logging.info("'Job' para comfy_handler creado con éxito.")
        
        # --- 4. EJECUTAR Y CAPTURAR EL RESULTADO ---
        logging.info("Invocando a comfy_handler.handler...")
        comfy_output = None
        all_results = []
        
        result_generator = comfy_handler.handler(comfy_job)
        for result in result_generator:
            logging.info(f"Recibido resultado del generador: {result}")
            all_results.append(result)
            comfy_output = result # El último resultado se guarda
        
        logging.info(f"Ejecución de comfy_handler finalizada. Se recibieron {len(all_results)} resultados.")

        if comfy_output is None:
            error_msg = "El handler de ComfyUI no produjo ningún output."
            logging.error(error_msg)
            return {"error": error_msg}

        if isinstance(comfy_output, str):
            error_msg = f"Error interno del comfy_handler (devolvió un string): {comfy_output}"
            logging.error(error_msg)
            return {"error": error_msg}
        
        if not isinstance(comfy_output, dict):
            error_msg = f"El comfy_handler devolvió un tipo de dato inesperado: {type(comfy_output)}"
            logging.error(error_msg)
            return {"error": error_msg}

        # --- 5. BUSCAR Y VERIFICAR EL ARCHIVO DE SALIDA ---
        logging.info("Procesando el output final de ComfyUI para encontrar la imagen...")
        
        # El output de ComfyUI es un diccionario donde las claves son IDs de nodos.
        for node_id, node_data in comfy_output.items():
            if 'images' in node_data:
                for image_data in node_data['images']:
                    filename = image_data.get('filename')
                    full_persistent_path = os.path.join(output_dir, filename)
                    logging.info(f"Imagen encontrada en el output: '{filename}'. Verificando en: '{full_persistent_path}'")
                    
                    if os.path.exists(full_persistent_path):
                        logging.info("¡ÉXITO! El archivo existe. Devolviendo la ruta.")
                        return { "image_pod_path": full_persistent_path }
                    else:
                        error_msg = f"El archivo '{filename}' fue reportado por ComfyUI pero NO fue encontrado en la ruta de salida esperada."
                        logging.error(error_msg)
                        return {"error": error_msg}

        error_msg = "Workflow completado pero no se encontraron imágenes en el output final de ComfyUI."
        logging.error(error_msg)
        return {"error": error_msg, "raw_output": comfy_output}

    except Exception as e:
        # Usamos exc_info=True para obtener un traceback completo en los logs
        logging.error(f"Error fatal en morpheus_handler: {str(e)}", exc_info=True)
        return {"error": f"Error fatal en morpheus_handler: {str(e)}"}

# Punto de entrada para el servidor serverless de RunPod
runpod.serverless.start({"handler": morpheus_handler})
