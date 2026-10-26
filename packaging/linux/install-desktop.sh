#!/usr/bin/env bash
set -e

# ==============================================================================
# Orpheus - Script de Instalación y Registro de Escritorio para Linux (Fedora)
# Registra el icono oficial y el archivo .desktop en las rutas de usuario XDG
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=========================================================="
echo "   Orpheus - Registro de Escritorio e Icono (Linux)       "
echo "=========================================================="

# 1. Definir rutas estándar del usuario (XDG)
XDG_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
APPS_DIR="$XDG_DATA_DIR/applications"
ICONS_512_DIR="$XDG_DATA_DIR/icons/hicolor/512x512/apps"
ICONS_128_DIR="$XDG_DATA_DIR/icons/hicolor/128x128/apps"

echo "[1/4] Creando directorios XDG locales..."
mkdir -p "$APPS_DIR"
mkdir -p "$ICONS_512_DIR"
mkdir -p "$ICONS_128_DIR"

# 2. Instalar iconos oficiales de Orpheus
echo "[2/4] Copiando iconos a $XDG_DATA_DIR/icons/hicolor/..."
if [ -f "$SCRIPT_DIR/org.heyzell.Orpheus.png" ]; then
  cp -f "$SCRIPT_DIR/org.heyzell.Orpheus.png" "$ICONS_512_DIR/org.heyzell.Orpheus.png"
elif [ -f "$PROJECT_ROOT/assets/icon/app_icon.png" ]; then
  cp -f "$PROJECT_ROOT/assets/icon/app_icon.png" "$ICONS_512_DIR/org.heyzell.Orpheus.png"
fi

if [ -f "$SCRIPT_DIR/icons/128x128.png" ]; then
  cp -f "$SCRIPT_DIR/icons/128x128.png" "$ICONS_128_DIR/org.heyzell.Orpheus.png"
elif [ -f "$SCRIPT_DIR/org.heyzell.Orpheus.png" ]; then
  cp -f "$SCRIPT_DIR/org.heyzell.Orpheus.png" "$ICONS_128_DIR/org.heyzell.Orpheus.png"
fi

# 3. Determinar ruta del ejecutable y configurar .desktop
echo "[3/4] Configurando lanzador org.heyzell.Orpheus.desktop..."
TARGET_DESKTOP="$APPS_DIR/org.heyzell.Orpheus.desktop"
cp -f "$SCRIPT_DIR/org.heyzell.Orpheus.desktop" "$TARGET_DESKTOP"

EXEC_PATH=""
if [ -n "$1" ] && [ -x "$1" ]; then
  EXEC_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
elif [ -x "$PROJECT_ROOT/build/linux/x64/release/bundle/orpheus" ]; then
  EXEC_PATH="$PROJECT_ROOT/build/linux/x64/release/bundle/orpheus"
elif [ -x "$PROJECT_ROOT/build/linux/x64/debug/intermediates_do_not_run/orpheus" ]; then
  EXEC_PATH="$PROJECT_ROOT/build/linux/x64/debug/intermediates_do_not_run/orpheus"
elif command -v orpheus >/dev/null 2>&1; then
  EXEC_PATH="$(command -v orpheus)"
fi

if [ -n "$EXEC_PATH" ]; then
  echo "    Apuntando ejecutable a: $EXEC_PATH"
  sed -i "s|^Exec=orpheus|Exec=$EXEC_PATH|" "$TARGET_DESKTOP"
else
  echo "    Nota: Manteniendo 'Exec=orpheus %U' (ejecutable del sistema o PATH)."
fi

chmod +x "$TARGET_DESKTOP"

# 4. Actualizar bases de datos y cachés del entorno de escritorio
echo "[4/4] Actualizando cachés de escritorio de Fedora / GNOME..."
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPS_DIR"
  echo "    ✓ update-desktop-database ejecutado correctamente."
else
  echo "    (update-desktop-database no encontrado en PATH, omitiendo)"
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$XDG_DATA_DIR/icons/hicolor" 2>/dev/null || true
  echo "    ✓ gtk-update-icon-cache ejecutado para hicolor."
else
  echo "    (gtk-update-icon-cache no encontrado en PATH, omitiendo)"
fi

echo "=========================================================="
echo " ¡Instalación exitosa! Orpheus ahora está registrado con  "
echo " su icono oficial en GNOME Shell / Fedora Dock.           "
echo "=========================================================="
