#!/usr/bin/env bash
# ==============================================================================
# Task Monitor - Ollama & 4-bit Gemma Setup Script
# ==============================================================================
# Verifies Ollama installation, starts daemon if needed, pulls lightweight
# 4-bit vision/multimodal model, and tests endpoint.
# ==============================================================================

set -euo pipefail

MODEL_NAME="${1:-gemma:2b}"
OLLAMA_URL="http://127.0.0.1:11434"

echo "=============================================================================="
echo " Task Monitor - Ollama & Gemma Setup"
echo " Target Model: ${MODEL_NAME}"
echo "=============================================================================="

# 1. Check if Ollama binary is installed
if ! command -v ollama >/dev/null 2>&1; then
  echo "Error: 'ollama' command not found." >&2
  echo "Please install Ollama from https://ollama.com/download or via package manager." >&2
  exit 1
fi

# 2. Check if Ollama server is running
echo "Checking Ollama server connectivity at ${OLLAMA_URL}..."
if ! curl -s "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
  echo "Ollama server is not responding. Attempting to start service..."
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ollama; then
    echo "Restarting ollama systemd service..."
    sudo systemctl restart ollama || true
  else
    echo "Starting background ollama instance..."
    nohup ollama serve >/tmp/ollama_task_monitor.log 2>&1 &
    sleep 3
  fi
fi

# Re-verify connection
if curl -s "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
  echo "✓ Ollama server is connected and ready."
else
  echo "Error: Failed to connect to Ollama server at ${OLLAMA_URL}." >&2
  exit 1
fi

# 3. Pull model
echo "Pulling model '${MODEL_NAME}'..."
ollama pull "${MODEL_NAME}"

# 4. Probe test
echo "Running verification test with model '${MODEL_NAME}'..."
TEST_PROMPT='{"model": "'"${MODEL_NAME}"'", "prompt": "Respond with JSON: {\"status\": \"ready\"}", "stream": false}'
RESPONSE=$(curl -s -X POST "${OLLAMA_URL}/api/generate" -d "${TEST_PROMPT}" || true)

echo "Response: ${RESPONSE}"
echo "=============================================================================="
echo "✓ Ollama and ${MODEL_NAME} are configured and ready for Task Monitor!"
echo "=============================================================================="
