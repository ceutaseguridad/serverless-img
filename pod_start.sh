#!/bin/bash

# ==============================================================================
# SCRIPT DE DIAGNÓSTICO DE DEPENDENCIAS v1
# Objetivo: Instalar y verificar el estado de las librerías de Python.
# NO arranca ComfyUI.
# ==============================================================================

set -e
set -o pipefail

# --- FASE 0: DEFINIR RUTAS Y FICHERO DE LOG ---
NETWORK_VOLUME_PATH="/runpod-volume"
LOG_FILE="${NETWORK_VOLUME_PATH}/diagnostic_log.txt"

# Limpiar el log de ejecuciones anteriores
echo "--- INICIO DEL LOG DE DIAGNÓSTICO ---" > "${LOG_FILE}"
echo "Fecha y Hora: $(date)" >> "${LOG_FILE}"
echo "=======================================" >> "${LOG_FILE}"


# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS BASE ---
echo "[DIAGNÓSTICO] FASE 1: Instalando dependencias base..."
apt-get update > /dev/null 2>&1 && apt-get install -y git > /dev/null 2>&1
pip install --upgrade pip

# Forzar instalación de dependencias base de la aplicación
pip install --upgrade --no-cache-dir --force-reinstall insightface==0.7.3 facexlib timm ftfy requests xformers "huggingface-hub<1.0" >> "${LOG_FILE}" 2>&1

echo "--- ESTADO DESPUÉS DE LA INSTALACIÓN BASE ---" >> "${LOG_FILE}"
pip list | grep -E "onnx|insightface" >> "${LOG_FILE}"
echo "=======================================" >> "${LOG_FILE}"


# --- FASE 2: INSTALACIÓN DE DEPENDENCIAS DE NODOS ---
# (Simulamos lo que haría tu script original)
# Nota: Asumo que los nodos ya están clonados en tu volumen persistente.
echo "[DIAGNÓSTICO] FASE 2: Instalando dependencias de nodos..."

# Dependencias de PuLID (el sospechoso principal del conflicto)
REQ_PULID="/runpod-volume/morpheus_model_cache/ComfyUI-PuLID/requirements.txt"
if [ -f "$REQ_PULID" ]; then
    echo "Instalando requisitos de ComfyUI-PuLID..." >> "${LOG_FILE}"
    pip install -r "$REQ_PULID" >> "${LOG_FILE}" 2>&1
else
    echo "ADVERTENCIA: No se encontró $REQ_PULID" >> "${LOG_FILE}"
fi

echo "--- ESTADO DESPUÉS DE INSTALAR REQUISITOS DE PuLID ---" >> "${LOG_FILE}"
pip list | grep -E "onnx|insightface|onnxruntime" >> "${LOG_FILE}"
echo "=======================================" >> "${LOG_FILE}"

# (Puedes añadir aquí la instalación de requisitos de otros nodos si es necesario)


# --- FASE 3: VERIFICACIÓN FINAL Y MANTENER VIVO ---
echo "[DIAGNÓSTICO] Verificación final con pip check..." >> "${LOG_FILE}"
pip check >> "${LOG_FILE}" 2>&1 || true # Usamos '|| true' para que no falle el script si pip check encuentra errores

echo "--- FIN DEL LOG DE DIAGNÓSTICO ---" >> "${LOG_FILE}"
echo "[DIAGNÓSTICO] Proceso completado. El log se ha guardado en ${LOG_FILE}"
echo "[DIAGNÓSTICO] El worker se mantendrá activo durante 5 minutos para permitir la recuperación del log."

# Mantener el contenedor vivo durante 300 segundos (5 minutos)
sleep 300
