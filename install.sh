#!/usr/bin/env bash
# ==============================================================================
# Orpheus - Instalador Automatizado para Linux
# ==============================================================================
# Este script instala Orpheus en el entorno de usuario XDG estándar:
#   - Binario y dependencias: ~/.local/share/orpheus/
#   - Icono del sistema:     ~/.local/share/icons/hicolor/512x512/apps/
#   - Acceso de escritorio:  ~/.local/share/applications/org.heyzell.Orpheus.desktop
# ==============================================================================

set -euo pipefail

# ── Colores de Terminal ────────────────────────────────────────────────────────
CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_CYAN="\033[1;36m"
CLR_GREEN="\033[1;32m"
CLR_YELLOW="\033[1;33m"
CLR_RED="\033[1;31m"
CLR_DIM="\033[2m"

echo -e "${CLR_CYAN}==========================================================${CLR_RESET}"
echo -e "${CLR_BOLD}       Orpheus - Instalador Automatizado para Linux       ${CLR_RESET}"
echo -e "${CLR_CYAN}==========================================================${CLR_RESET}"

# 1. Detección de Directorio Origen del Bundle
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR=""

if [ -f "$SCRIPT_DIR/orpheus" ]; then
  SOURCE_DIR="$SCRIPT_DIR"
elif [ -f "$SCRIPT_DIR/build/linux/x64/release/bundle/orpheus" ]; then
  SOURCE_DIR="$SCRIPT_DIR/build/linux/x64/release/bundle"
elif [ -f "$SCRIPT_DIR/bundle/orpheus" ]; then
  SOURCE_DIR="$SCRIPT_DIR/bundle"
else
  echo -e "${CLR_RED}Error:${CLR_RESET} No se encontró el binario ejecutable 'orpheus'."
  echo -e "Asegúrate de ejecutar este instalador dentro de la carpeta descomprimida del release."
  exit 1
fi

echo -e "${CLR_DIM}Origen de instalación: $SOURCE_DIR${CLR_RESET}"

# 2. Definición y Creación de Rutas XDG
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_INSTALL_DIR="$XDG_DATA_HOME/orpheus"
APPLICATIONS_DIR="$XDG_DATA_HOME/applications"
ICONS_512_DIR="$XDG_DATA_HOME/icons/hicolor/512x512/apps"

echo -e "\n${CLR_BOLD}[1/4]${CLR_RESET} Creando directorios del sistema XDG..."
mkdir -p "$APP_INSTALL_DIR"
mkdir -p "$APPLICATIONS_DIR"
mkdir -p "$ICONS_512_DIR"
echo -e "      ${CLR_GREEN}✓ Carpetas preparadas en $XDG_DATA_HOME${CLR_RESET}"

# 3. Copiado de Archivos y Dependencias del Bundle
echo -e "${CLR_BOLD}[2/4]${CLR_RESET} Copiando binarios y librerías en $APP_INSTALL_DIR..."
# Copiamos todos los elementos del bundle excluyendo este instalador
for item in "$SOURCE_DIR"/*; do
  item_name="$(basename "$item")"
  if [ "$item_name" != "install.sh" ]; then
    cp -rf "$item" "$APP_INSTALL_DIR/"
  fi
done

# Permisos de ejecución obligatorios para el binario
chmod +x "$APP_INSTALL_DIR/orpheus"
echo -e "      ${CLR_GREEN}✓ Archivos de aplicación instalados y permisos otorgados${CLR_RESET}"

# 4. Instalación de Icono de la Aplicación
echo -e "${CLR_BOLD}[3/4]${CLR_RESET} Instalando icono de alta resolución..."
ICON_INSTALLED=false
for icon_candidate in \
  "$SOURCE_DIR/org.heyzell.Orpheus.png" \
  "$SOURCE_DIR/data/flutter_assets/assets/icon/app_icon.png" \
  "$SCRIPT_DIR/packaging/linux/org.heyzell.Orpheus.png" \
  "$SCRIPT_DIR/linux/runner/resources/app_icon.png" \
  "$SCRIPT_DIR/assets/icon/app_icon.png"; do
  if [ -f "$icon_candidate" ]; then
    cp -f "$icon_candidate" "$ICONS_512_DIR/org.heyzell.Orpheus.png"
    ICON_INSTALLED=true
    break
  fi
done

if [ "$ICON_INSTALLED" = true ]; then
  echo -e "      ${CLR_GREEN}✓ Icono instalado en $ICONS_512_DIR/org.heyzell.Orpheus.png${CLR_RESET}"
else
  echo -e "      ${CLR_YELLOW}⚠ No se encontró el icono para copiar, se usará el fallback del sistema.${CLR_RESET}"
fi

# 5. Generación del Archivo de Escritorio (.desktop)
echo -e "${CLR_BOLD}[4/4]${CLR_RESET} Registrando acceso directo de escritorio..."
DESKTOP_FILE="$APPLICATIONS_DIR/org.heyzell.Orpheus.desktop"

cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=Orpheus
Comment=Reproductor y gestor de música multimedia
Exec=$HOME/.local/share/orpheus/orpheus
Icon=org.heyzell.Orpheus
Terminal=false
Categories=AudioVideo;Player;Music;
StartupWMClass=org.heyzell.Orpheus
EOF

chmod +x "$DESKTOP_FILE"
echo -e "      ${CLR_GREEN}✓ Lanzador creado en $DESKTOP_FILE${CLR_RESET}"

# Actualizar base de datos de escritorios e icono
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$XDG_DATA_HOME/icons/hicolor" 2>/dev/null || true
fi

# 6. Mensaje de Éxito
echo -e "\n${CLR_GREEN}==========================================================${CLR_RESET}"
echo -e "${CLR_GREEN}${CLR_BOLD}   ¡Orpheus se ha instalado correctamente en tu equipo!   ${CLR_RESET}"
echo -e "${CLR_GREEN}==========================================================${CLR_RESET}"
echo -e "  • Ubicación:      ${CLR_BOLD}$APP_INSTALL_DIR/orpheus${CLR_RESET}"
echo -e "  • Lanzador:       ${CLR_BOLD}$DESKTOP_FILE${CLR_RESET}"
echo -e "  • Icono:          ${CLR_BOLD}$ICONS_512_DIR/org.heyzell.Orpheus.png${CLR_RESET}"
echo ""
echo -e "Orpheus ya está disponible en tu menú de aplicaciones (GNOME, KDE, XFCE)."
echo -e "También puedes iniciarlo ejecutando: ${CLR_CYAN}$APP_INSTALL_DIR/orpheus${CLR_RESET}\n"
