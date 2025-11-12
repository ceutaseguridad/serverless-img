bash -c "rm -rf /workspace/morpheus_config && git clone https://github.com/ceutaseguridad/serverless-img.git /workspace/morpheus_config && cd /workspace/morpheus_config && chmod +x pod_start.sh && ./pod_start.sh"```

**2. `pod_start.sh` (Script de Búsqueda Pura):**
Reemplaza TODO el contenido de tu `pod_start.sh` con esto. No hace nada más que buscar.

```bash
#!/bin/bash
# ==============================================================================
# Script de Búsqueda Definitiva - Misión: Encontrar los putos señuelos.
# ==============================================================================

set -e

echo "--- [BÚSQUEDA] INICIANDO SCRIPT DE VERIFICACIÓN ---"
date
echo " "
echo "Voy a buscar en TODO el sistema de archivos los archivos señuelo."
echo "La ruta que aparezca aquí es la ruta REAL dentro del worker serverless."
echo " "

# Damos 5 segundos para asegurar que cualquier montaje de disco se complete.
sleep 5

echo "--- [BÚSQUEDA] RESULTADOS DE LA BÚSQUEDA: ---"

# El comando 'find' buscará en todas partes los archivos que hemos creado.
find / -name "este_archivo_se_creo_en_*.txt" 2>/dev/null

echo " "
echo "--- [BÚSQUEDA] BÚSQUEDA FINALIZADA ---"
echo "Si no ha aparecido ninguna ruta arriba, el worker no ha encontrado NINGUNO de los señuelos."

# Mantenemos el worker vivo para poder leer el log con calma.
sleep infinity
