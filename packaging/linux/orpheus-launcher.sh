#!/bin/bash
set -e

# Export standard XDG environment fallbacks if unset
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# Ensure libvlc / mpv dynamic libraries are discoverable in Flatpak runtime
export LD_LIBRARY_PATH="/app/lib:/app/orpheus/lib:$LD_LIBRARY_PATH"

# Run Orpheus passing all command line arguments
exec /app/orpheus/orpheus "$@"
