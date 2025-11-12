import json
import runpod

def morpheus_handler(job):
    """
    Handler de diagnóstico. Su única función es imprimir el objeto 'job' que recibe.
    """
    print("--- INICIO DE MORPHEUS_HANDLER (v16 - DIAGNÓSTICO) ---")
    
    # Imprimimos el objeto job completo para ver su estructura real.
    print("DEBUG: Objeto 'job' recibido por el handler:")
    try:
        # La forma más limpia de verlo es como un JSON formateado.
        print(json.dumps(job, indent=2))
    except Exception as e:
        print(f"No se pudo serializar 'job' a JSON: {e}")
        print(f"Contenido de 'job' como string: {job}")

    # Devolvemos un resultado simple y estático para confirmar que el flujo de retorno funciona.
    # Esto NO ejecutará ComfyUI.
    return {
        "status": "DEBUG_SUCCESS",
        "message": "Handler recibió el trabajo y lo imprimió correctamente."
    }

print("--- MORPHEUS_HANDLER.PY (v16 - DIAGNÓSTICO) CARGADO, INICIANDO SERVIDOR ---")
runpod.serverless.start({"handler": morpheus_handler})
