import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Flatpak & Linux Desktop Packaging Validation', () {
    test('Desktop Entry file exists and contains valid metadata', () {
      final desktopFile = File('packaging/linux/org.heyzell.Orpheus.desktop');
      expect(desktopFile.existsSync(), isTrue, reason: 'Desktop entry file must exist');

      final content = desktopFile.readAsStringSync();
      expect(content.contains('[Desktop Entry]'), isTrue);
      expect(content.contains('Name=Orpheus'), isTrue);
      expect(content.contains('Icon=org.heyzell.Orpheus'), isTrue);
      expect(content.contains('Exec=orpheus %U'), isTrue);
      expect(content.contains('Categories=AudioVideo;Audio;Player;Music;'), isTrue);
      expect(content.contains('Actions=PlayPause;Next;Previous;'), isTrue);
    });

    test('AppStream Metainfo file exists and satisfies Flathub spec', () {
      final metainfoFile = File('packaging/linux/org.heyzell.Orpheus.metainfo.xml');
      expect(metainfoFile.existsSync(), isTrue, reason: 'Metainfo file must exist');

      final xml = metainfoFile.readAsStringSync();
      expect(xml.contains('<id>org.heyzell.Orpheus</id>'), isTrue);
      expect(xml.contains('type="desktop-application"'), isTrue);
      expect(xml.contains('<name>Orpheus</name>'), isTrue);
      expect(xml.contains('<binary>orpheus</binary>'), isTrue);
      expect(xml.contains('<launchable type="desktop-id">org.heyzell.Orpheus.desktop</launchable>'), isTrue);
      expect(xml.contains('<content_rating type="oars-1.1" />'), isTrue);
    });

    test('Flatpak manifest file exists and specifies GNOME 46 runtime and permissions', () {
      final manifestFile = File('flatpak/org.heyzell.Orpheus.yaml');
      expect(manifestFile.existsSync(), isTrue, reason: 'Flatpak manifest must exist');

      final yaml = manifestFile.readAsStringSync();
      expect(yaml.contains('app-id: org.heyzell.Orpheus'), isTrue);
      expect(yaml.contains('runtime: org.gnome.Platform'), isTrue);
      expect(yaml.contains("runtime-version: '46'"), isTrue);
      expect(yaml.contains('command: orpheus'), isTrue);

      // Sandboxing permissions verification
      expect(yaml.contains('--socket=wayland'), isTrue);
      expect(yaml.contains('--socket=fallback-x11'), isTrue);
      expect(yaml.contains('--socket=pulseaudio'), isTrue);
      expect(yaml.contains('--device=dri'), isTrue);
      expect(yaml.contains('--share=network'), isTrue);
      expect(yaml.contains('--filesystem=xdg-music:ro'), isTrue);
      expect(yaml.contains('--filesystem=home:ro'), isTrue);
      expect(yaml.contains('--own-name=org.mpris.MediaPlayer2.orpheus'), isTrue);
    });

    test('Packaging icon assets exist and are non-empty', () {
      final icon128 = File('packaging/linux/icons/128x128.png');
      final icon512 = File('packaging/linux/icons/512x512.png');
      final iconRoot = File('packaging/linux/org.heyzell.Orpheus.png');

      expect(icon128.existsSync(), isTrue);
      expect(icon128.lengthSync(), greaterThan(0));

      expect(icon512.existsSync(), isTrue);
      expect(icon512.lengthSync(), greaterThan(0));

      expect(iconRoot.existsSync(), isTrue);
      expect(iconRoot.lengthSync(), greaterThan(0));
    });

    test('Flatpak launcher script is executable and contains environment setup', () {
      final launcher = File('packaging/linux/orpheus-launcher.sh');
      expect(launcher.existsSync(), isTrue);

      final content = launcher.readAsStringSync();
      expect(content.contains('#!/bin/bash'), isTrue);
      expect(content.contains('LD_LIBRARY_PATH'), isTrue);
      expect(content.contains('/app/orpheus/orpheus'), isTrue);
    });
  });
}
