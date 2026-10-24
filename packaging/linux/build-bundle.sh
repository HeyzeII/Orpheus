#!/usr/bin/env bash
set -e

# Orpheus Linux Release Packager
echo "=========================================================="
echo "      Orpheus - Compilación y Empaquetado para Linux      "
echo "=========================================================="

if [[ "$OSTYPE" != "linux-gnu"* ]]; then
  echo "Error: 'flutter build linux' requiere un entorno Linux (o contenedor Linux)."
  echo "Sistema operativo detectado: $OSTYPE"
  exit 1
fi

echo "[1/4] Obteniendo dependencias de Flutter..."
flutter pub get

echo "[2/4] Compilando binario optimizado Release para Linux x64..."
flutter build linux --release

BUNDLE_DIR="build/linux/x64/release/bundle"
ARCHIVE_PATH="orpheus-linux-x64.tar.gz"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "Error: No se encontró la carpeta del bundle en $BUNDLE_DIR"
  exit 1
fi

echo "[3/4] Incluyendo metadatos de escritorio e iconos en el bundle..."
cp -f packaging/linux/org.heyzell.Orpheus.desktop "$BUNDLE_DIR/" 2>/dev/null || true
cp -f packaging/linux/org.heyzell.Orpheus.png "$BUNDLE_DIR/" 2>/dev/null || true

echo "[4/4] Comprimiendo distribución a $ARCHIVE_PATH..."
tar -czvf "$ARCHIVE_PATH" -C "$BUNDLE_DIR" .

echo "=========================================================="
echo " ¡Empaquetado exitoso! Archivo generado: $ARCHIVE_PATH"
echo "=========================================================="
