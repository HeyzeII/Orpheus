.PHONY: all test analyze update-linux run-linux bundle-linux clean

all: analyze test

## Ejecuta el analizador estático de Dart
analyze:
	dart analyze

## Ejecuta la suite de pruebas unitarias y de widgets
test:
	flutter test

## Compila, actualiza y registra Orpheus limpiamente en Linux
update-linux:
	./scripts/update_linux.sh

## Compila, actualiza e inicia Orpheus en Linux
run-linux:
	./scripts/update_linux.sh --run

## Genera el archivo tar.gz distribuible para Linux
bundle-linux:
	./packaging/linux/build-bundle.sh

## Limpia la caché y los artefactos de compilación
clean:
	flutter clean
