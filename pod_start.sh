#!/bin/bash

# ==============================================================================
# SCRIPT DE DIAGNÓSTICO DE CRASH LOOP v2
# Objetivo: Instalar paquetes uno por uno para aislar el que causa el fallo.
# ==============================================================================

set -e
set -o pipefail

# --- FASE 0: DEFINIR RUTAS Y FICHERO DE LOG ---
NETWORK_VOLUME_PATH="/runpod-volume"
LOG_FILE="${NETWORK_VOLUME_PATH}/diagnostic_crash_log.txt"

# Limpiar el log de ejecuciones anteriores
echo "--- INICIO DEL LOG DE DIAGNÓSTICO DE CRASH ---" > "${LOG_FILE}"
echo "Fecha y Hora: $(date)" >> "${LOG_FILE}"
echo "=======================================" >> "${LOG_FILE}"


# --- FASE 1: INSTALACIÓN DE DEPENDENCIAS SECUENCIAL ---
echo "[DIAGNÓSTICO] FASE 1: Instalando dependencias base una por una..."
apt-get update > /dev/null 2>&1 && apt-get install -y git > /dev/null 2>&1
pip install --upgrade pip

# Vamos a instalar los paquetes uno por uno. El que cause el reinicio es el culpable.
# Redirigimos la salida de cada comando al log.

echo "Instalando huggingface-hub..." >> "${LOG_FILE}"
pip install --no-cache-dir "huggingface-hub<1.0" >> "${LOG_FILE}" 2>&1

echo "Instalando xformers..." >> "${LOG_FILE}"
# Xformers y Torch son los principales sospechosos.
pip install --no-cache-dir xformers >> "${LOG_FILE}" 2>&1

echo "Instalando facexlib..." >> "${LOG_FILE}"
pip install --no-cache-dir facexlib >> "${LOG_FILE}" 2>&1

echo "Instalando timm..." >> "${LOG_FILE}"
pip install --no-cache-dir timm >> "${LOG_FILE}" 2>&1

echo "Instalando ftfy..." >> "${LOG_FILE}"
pip install --no-cache-dir ftfy >> "${LOG_FILE}" 2>&1

# Insightface lo dejamos para el final, ya que depende de muchos otros.
echo "Instalando insightface..." >> "${LOG_FILE}"
pip install --no-cache-dir --force-reinstall insightface==0.7.3 >> "${LOG_FILE}" 2>&1

echo "--- ¡TODAS LAS DEPENDENCIAS BASE SE INSTALARON CON ÉXITO! ---" >> "${LOG_FILE}"
echo "--- ESTADO DESPUÉS DE LA INSTALACIÓN BASE ---" >> "${LOG_FILE}"
pip list | grep -E "onnx|insightface|torch|xformers" >> "${LOG_FILE}"
echo "=======================================" >> "${LOG_FILE}"


# --- FASE 2: INSTALACIÓN DE DEPENDENCIAS DE NODOS ---
# (Si llega hasta aquí, el problema no estaba en la base)
echo "[DIAGNÓSTICO] FASE 2: Instalando dependencias de nodos..."

REQ_PULID="/runpod-volume/morpheus_model_cache/ComfyUI-PuLID/requirements.txt"
if [ -f "$REQ_PULID" ]; then
    echo "Instalando requisitos de ComfyUI-PuLID..." >> "${LOG_FILE}"
    pip install -r "$REQ_PULID" >> "${LOG_FILE}" 2>&1
else
    echo "ADVERTENCIA: No se encontró $REQ_PULID" >> "${LOG_FILE}"
fi

echo "--- ESTADO DESPUÉS DE INSTALAR REQUISITOS DE PuLID ---" >> "${LOG_FILE}"
pip list | grep -E "onnx|insightface|onnxruntime|torch|xformers" >> "${LOG_FILE}"
echo "=======================================" >> "${LOG_FILE}"


# --- FASE 3: MANTENER VIVO SI TODO FUNCIONA ---
echo "[DIAGNÓSTICO] Proceso completado. El log se ha guardado en ${LOG_FILE}"
echo "[DIAGNÓSTICO] El worker se mantendrá activo durante 5 minutos para permitir la recuperación del log."

sleep 300
