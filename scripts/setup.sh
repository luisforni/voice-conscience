#!/usr/bin/env bash
# Simple setup script for Ubuntu: installs Python, pip, and guidance for Ollama/Whisper
set -e
echo "Updating apt and installing dependencies..."
sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl git build-essential

echo "Python and pip installed."
echo "For Ollama and Whisper, follow their official install guides:" 
echo " - Ollama: https://docs.ollama.com/ (install for your distro)"
echo " - Whisper (openai-whisper): recommended to use a Python venv and pip install -r services/backend/requirements.txt"

echo "To finish setup for this repo (create submodules):"
echo "  git submodule init && git submodule update --remote --recursive"

echo "Setup complete."
