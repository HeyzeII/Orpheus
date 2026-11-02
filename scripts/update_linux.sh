#!/usr/bin/env bash
# ==============================================================================
# Orpheus - Script de Instalación y Actualización Automatizada para Linux
# ==============================================================================
# Uso:
#   ./scripts/update_linux.sh          Compila e instala/actualiza la versión Release
#   ./scripts/update_linux.sh --run    Actualiza e inicia Orpheus inmediatamente
#   ./scripts/update_linux.sh --debug  Compila e instala la versión Debug
#   ./scripts/update_linux.sh --help   Muestra la ayuda
# ==============================================================================

set -euo pipefail

# ── Colores y Estilos ──────────────────────────────────────────────────────────
CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_CYAN="\033[1;36m"
CLR_GREEN="\033[1;32m"
CLR_YELLOW="\033[1;33m"
CLR_RED="\033[1;31m"
CLR_DIM="\033[2m"

# ── Detección de Rutas ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

RUN_AFTER=false
BUILD_MODE="release"

# ── Procesar Argumentos ───────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --run|-r)
      RUN_AFTER=true
      ;;
    --debug|-d)
      BUILD_MODE="debug"
      ;;
    --help|-h)
      echo -e "${CLR_BOLD}Orpheus Linux Updater${CLR_RESET}"
      echo ""
      echo "Uso: ./scripts/update_linux.sh [opciones]"
      echo ""
      echo "Opciones:"
      echo "  -r, --run      Inicia Orpheus automáticamente al terminar la actualización."
      echo "  -d, --debug    Compila en modo debug en lugar de release."
      echo "  -h, --help     Muestra esta ayuda."
      echo ""
      exit 0
      ;;
    *)
      echo -e "${CLR_YELLOW}Advertencia:${CLR_RESET} Argumento desconocido '$arg' ignorado."
      ;;
  esac
done

echo -e "${CLR_CYAN}==========================================================${CLR_RESET}"
echo -e "${CLR_BOLD}    Orpheus - Actualización Automatizada para Linux       ${CLR_RESET}"
echo -e "${CLR_CYAN}==========================================================${CLR_RESET}"

# 1. Verificar Entorno
if [[ "${OSTYPE:-}" != "linux-gnu"* && "$(uname -s)" != "Linux" ]]; then
  echo -e "${CLR_RED}Error:${CLR_RESET} Este script debe ejecutarse en un entorno Linux (detectado: $(uname -s))."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo -e "${CLR_RED}Error:${CLR_RESET} No se encontró 'flutter' en el PATH del sistema."
  exit 1
fi

# 2. Cerrar instancias en ejecución para evitar errores de binario ocupado (ETXTBSY)
echo -e "${CLR_BOLD}[1/5]${CLR_RESET} Verificando procesos activos de Orpheus..."
if pgrep -x orpheus >/dev/null 2>&1; then
  echo -e "      ${CLR_YELLOW}Cerrando instancia en ejecución de Orpheus para actualizar...${CLR_RESET}"
  pkill -x orpheus 2>/dev/null || true
  sleep 0.8
fi

# 3. Compilación
echo -e "${CLR_BOLD}[2/5]${CLR_RESET} Resolviendo dependencias y compilando ($BUILD_MODE)..."
flutter pub get

if [ "$BUILD_MODE" = "release" ]; then
  flutter build linux --release
  BUNDLE_DIR="$PROJECT_ROOT/build/linux/x64/release/bundle"
else
  flutter build linux --debug
  BUNDLE_DIR="$PROJECT_ROOT/build/linux/x64/debug/bundle"
fi

if [ ! -d "$BUNDLE_DIR" ] || [ ! -f "$BUNDLE_DIR/orpheus" ]; then
  echo -e "${CLR_RED}Error:${CLR_RESET} La compilación no generó el bundle esperado en $BUNDLE_DIR"
  exit 1
fi

# 4. Rutas Estándar XDG del Usuario
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_INSTALL_DIR="$XDG_DATA_HOME/orpheus/app"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$XDG_DATA_HOME/applications"
ICONS_512_DIR="$XDG_DATA_HOME/icons/hicolor/512x512/apps"
ICONS_128_DIR="$XDG_DATA_HOME/icons/hicolor/128x128/apps"

mkdir -p "$APP_INSTALL_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$DESKTOP_DIR"
mkdir -p "$ICONS_512_DIR"
mkdir -p "$ICONS_128_DIR"

# 5. Reemplazo limpio y desatendido del bundle
echo -e "${CLR_BOLD}[3/5]${CLR_RESET} Actualizando bundle en $APP_INSTALL_DIR..."
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$BUNDLE_DIR/" "$APP_INSTALL_DIR/"
else
  # Reemplazo limpio alternativo si rsync no está instalado
  rm -rf "${APP_INSTALL_DIR:?}"/*
  cp -a "$BUNDLE_DIR"/* "$APP_INSTALL_DIR/"
fi

# Crear / actualizar enlace simbólico en ~/.local/bin/orpheus
ln -sf "$APP_INSTALL_DIR/orpheus" "$BIN_DIR/orpheus"
chmod +x "$APP_INSTALL_DIR/orpheus" "$BIN_DIR/orpheus"
echo -e "      ${CLR_GREEN}✓ Binario actualizado en $BIN_DIR/orpheus${CLR_RESET}"

# 6. Registrar / Actualizar Lanzador .desktop e Iconos
echo -e "${CLR_BOLD}[4/5]${CLR_RESET} Registrando lanzador de escritorio e iconos XDG..."
if [ -f "$PROJECT_ROOT/packaging/linux/org.heyzell.Orpheus.png" ]; then
  cp -f "$PROJECT_ROOT/packaging/linux/org.heyzell.Orpheus.png" "$ICONS_512_DIR/org.heyzell.Orpheus.png"
  cp -f "$PROJECT_ROOT/packaging/linux/org.heyzell.Orpheus.png" "$ICONS_128_DIR/org.heyzell.Orpheus.png"
fi

TARGET_DESKTOP="$DESKTOP_DIR/org.heyzell.Orpheus.desktop"
if [ -f "$PROJECT_ROOT/packaging/linux/org.heyzell.Orpheus.desktop" ]; then
  cp -f "$PROJECT_ROOT/packaging/linux/org.heyzell.Orpheus.desktop" "$TARGET_DESKTOP"
  # Apuntar el lanzador al binario local en ~/.local/bin/orpheus
  sed -i "s|^Exec=orpheus|Exec=$BIN_DIR/orpheus|" "$TARGET_DESKTOP" || true
  chmod +x "$TARGET_DESKTOP"
fi

# Actualizar cachés de escritorio de Linux (GNOME / KDE)
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$XDG_DATA_HOME/icons/hicolor" 2>/dev/null || true
fi

# 7. Resumen Final
echo -e "${CLR_BOLD}[5/5]${CLR_RESET} Verificando configuración del sistema..."
echo -e "${CLR_GREEN}==========================================================${CLR_RESET}"
echo -e "${CLR_GREEN} ¡Actualización completada exitosamente!                  ${CLR_RESET}"
echo -e "${CLR_GREEN}==========================================================${CLR_RESET}"
echo -e "  • Ubicación del binario:  ${CLR_BOLD}$APP_INSTALL_DIR/orpheus${CLR_RESET}"
echo -e "  • Enlace de ejecución:    ${CLR_BOLD}$BIN_DIR/orpheus${CLR_RESET}"
echo -e "  • Lanzador de escritorio: ${CLR_BOLD}$TARGET_DESKTOP${CLR_RESET}"

# Verificar si ~/.local/bin está en el PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo ""
  echo -e "${CLR_YELLOW}Nota:${CLR_RESET} '$BIN_DIR' no está en tu variable \$PATH."
  echo -e "Para ejecutar 'orpheus' directamente desde cualquier terminal, añade:"
  echo -e "  ${CLR_DIM}export PATH=\"\$HOME/.local/bin:\$PATH\"${CLR_RESET}"
  echo -e "en tu archivo ~/.bashrc o ~/.zshrc."
fi

# 8. Iniciar si se solicitó --run
if [ "$RUN_AFTER" = true ]; then
  echo ""
  echo -e "${CLR_CYAN}Iniciando Orpheus...${CLR_RESET}"
  nohup "$BIN_DIR/orpheus" >/dev/null 2>&1 &
  echo -e "${CLR_GREEN}✓ Orpheus iniciado en segundo plano.${CLR_RESET}"
fi
