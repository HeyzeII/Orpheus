import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/services/album_art_fetcher_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/audio_scanner.dart';
import '../../core/services/permission_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// Settings View — Configuration panel for managing scan directories,
/// running library scans, and resolving artist duplicate conflicts.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  List<String> _scanDirs = [];
  bool _isScanning = false;
  String _currentScanningFile = '';
  int _scannedCount = 0;
  int _addedCount = 0;
  int _updatedCount = 0;
  int _skippedCount = 0;
  final List<ScanResult> _pendingMergeConflicts = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await LocalDatabase.instance.getConfig();
    setState(() {
      _scanDirs = List.from(config.scanDirectories);
    });
  }

  Future<void> _addDirectory() async {
    final granted = await PermissionService.requestStoragePermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se requieren permisos de almacenamiento para escanear música.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      await LocalDatabase.instance.addScanDirectory(path);
      await _loadConfig();
    }
  }

  Future<void> _removeDirectory(String path) async {
    await LocalDatabase.instance.removeScanDirectory(path);
    await _loadConfig();
  }

  Future<void> _runScan() async {
    if (_scanDirs.isEmpty) return;
    setState(() {
      _isScanning = true;
      _currentScanningFile = '';
      _scannedCount = 0;
      _addedCount = 0;
      _updatedCount = 0;
      _skippedCount = 0;
      _pendingMergeConflicts.clear();
    });

    final scanner = AudioScannerService();
    for (final dir in _scanDirs) {
      try {
        await for (final result in scanner.scanDirectory(dir)) {
          setState(() {
            _scannedCount++;
            _currentScanningFile = result.filePath.split('/').last;
            switch (result.outcome) {
              case ScanOutcome.added:
                _addedCount++;
                break;
              case ScanOutcome.updated:
                _updatedCount++;
                break;
              case ScanOutcome.skipped:
                _skippedCount++;
                break;
              case ScanOutcome.pendingArtistMerge:
                _pendingMergeConflicts.add(result);
                break;
            }
          });
        }
      } catch (e) {
        debugPrint('Error scanning directory $dir: $e');
      }
    }

    // Trigger cover art fetching for the newly added tracks in the background
    AlbumArtFetcherService.instance.processLibrary();

    setState(() {
      _isScanning = false;
      _currentScanningFile = '¡Escaneo completado!';
    });
  }

  Future<void> _resolveMerge(ScanResult conflict, int index) async {
    final track = await LocalDatabase.instance.getTrackByFilePath(conflict.filePath);
    if (track != null) {
      track.artist = conflict.existingArtist;
      await LocalDatabase.instance.saveTrack(track);
    }
    setState(() {
      _pendingMergeConflicts.removeAt(index);
    });
  }

  Future<void> _resolveIgnore(ScanResult conflict, int index) async {
    if (conflict.candidateArtist != null && conflict.existingArtist != null) {
      await LocalDatabase.instance.addIgnoredArtistPair(
        artistA: conflict.candidateArtist!,
        artistB: conflict.existingArtist!,
      );
    }
    setState(() {
      _pendingMergeConflicts.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──────────────────────────────────────────────────────────
          Text(
            'Ajustes',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Administra tus carpetas de música y el motor de escaneo.',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 40),

          // ── Section: Folders ───────────────────────────────────────────────
          const Text(
            'CARPETAS DE MÚSICA',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 12),
          _buildFolderList(),
          const SizedBox(height: 16),
          _buildAddFolderButton(),

          const SizedBox(height: 40),

          // ── Section: Scanner ───────────────────────────────────────────────
          const Text(
            'ESCÁNER DE BIBLIOTECA',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(height: 12),
          _buildScannerPanel(),

          // ── Section: Merge Conflicts ───────────────────────────────────────
          _buildMergeConflicts(),

          // ── Section: Maintenance Tools ─────────────────────────────────────
          _buildMaintenanceTools(),
        ],
      ),
    );
  }

  Widget _buildFolderList() {
    if (_scanDirs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          children: [
            Icon(Icons.folder_off_rounded, color: AppTheme.textHint, size: 36),
            const SizedBox(height: 8),
            const Text(
              'No hay carpetas configuradas para escanear.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _scanDirs.length,
      itemBuilder: (context, idx) {
        final path = _scanDirs[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_rounded, color: AppTheme.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  path,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontFamily: 'Inter',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: Colors.redAccent,
                onPressed: _isScanning ? null : () => _removeDirectory(path),
                hoverColor: Colors.redAccent.withAlpha(20),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddFolderButton() {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.divider),
          foregroundColor: AppTheme.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: AppTheme.bgSurface,
        ),
        onPressed: _isScanning ? null : _addDirectory,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text(
          'Añadir Carpeta',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildScannerPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Indexación y Metadatos',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isScanning
                          ? 'Escaneando archivos en busca de música...'
                          : 'Actualiza tu biblioteca local con los archivos nuevos.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.bgDeep,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onPressed: _isScanning || _scanDirs.isEmpty ? null : _runScan,
                icon: _isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          color: AppTheme.bgDeep,
                        ),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  _isScanning ? 'Escaneando...' : 'Escanear ahora',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (_isScanning || _scannedCount > 0) ...[
            const SizedBox(height: 20),
            Container(height: 1, color: AppTheme.divider),
            const SizedBox(height: 16),
            if (_isScanning) ...[
              const LinearProgressIndicator(
                color: AppTheme.accent,
                backgroundColor: AppTheme.bgDeep,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatTile('Procesados', _scannedCount),
                _buildStatTile('Agregados', _addedCount),
                _buildStatTile('Actualizados', _updatedCount),
                _buildStatTile('Ignorados/Error', _skippedCount),
              ],
            ),
            if (_currentScanningFile.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _isScanning ? 'Procesando: $_currentScanningFile' : _currentScanningFile,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'Inter',
                  color: AppTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 9, color: AppTheme.textSecondary, letterSpacing: 1.0),
        ),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildMergeConflicts() {
    if (_pendingMergeConflicts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        const Text(
          'CONFLICTOS DE NOMBRES DE ARTISTAS',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'El escáner detectó artistas con nombres similares. Puedes unificarlos para mantener tu biblioteca limpia.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _pendingMergeConflicts.length,
          itemBuilder: (context, idx) {
            final conflict = _pendingMergeConflicts[idx];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                border: Border.all(color: AppTheme.divider),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Archivo: ${conflict.filePath.split('/').last}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                              fontFamily: 'Inter',
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: 'Se leyó el artista '),
                              TextSpan(
                                text: '"${conflict.candidateArtist}"',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent,
                                ),
                              ),
                              const TextSpan(text: ', pero se parece al artista existente '),
                              TextSpan(
                                text: '"${conflict.existingArtist}"',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.bgDeep,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onPressed: () => _resolveMerge(conflict, idx),
                    child: const Text(
                      'Combinar',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onPressed: () => _resolveIgnore(conflict, idx),
                    child: const Text(
                      'Ignorar',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _resetFailedMedia() async {
    setState(() => _isScanning = true);
    await LocalDatabase.instance.resetNotFoundMediaFlags();
    setState(() => _isScanning = false);

    if (!mounted) return;
    AppToast.showText(
      context,
      'Búsquedas fallidas (notFound) reseteadas. Re-intentando en segundo plano...',
      icon: Icons.check_circle_rounded,
    );

    // Trigger cover art fetching in the background to retry immediately
    AlbumArtFetcherService.instance.processLibrary();
  }

  Future<void> _clearLyricsCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.divider),
          ),
          title: const Text(
            '¿Limpiar caché de letras?',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Esto eliminará todas las letras descargadas de LRCLIB. La app volverá a buscar letras en internet cuando reproduzcas tus canciones.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Limpiar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() => _isScanning = true);
    await LocalDatabase.instance.clearLyricsCache();
    setState(() => _isScanning = false);

    if (!mounted) return;
    AppToast.showText(
      context,
      'Caché de letras limpiada con éxito.',
      icon: Icons.check_circle_rounded,
    );
  }

  Future<void> _resetApplication() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.divider),
          ),
          title: const Text(
            '¿Restablecer aplicación?',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Esta acción es irreversible. Se vaciará toda la biblioteca indexada (canciones, álbumes, artistas, playlists) y la configuración de carpetas locales. Tus archivos físicos de música no serán modificados.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restablecer', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    setState(() {
      _isScanning = true;
      _scanDirs.clear();
    });
    await AudioPlayerService.instance.stopAndReset();
    await LocalDatabase.instance.clearDatabase();
    await _loadConfig();

    setState(() => _isScanning = false);

    if (!mounted) return;
    AppToast.showText(
      context,
      'Aplicación restablecida por completo.',
      icon: Icons.check_circle_rounded,
    );
  }

  Widget _buildMaintenanceTools() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        const Text(
          'MANTENIMIENTO Y HERRAMIENTAS',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: [
              // Tool 1: Clear Lyrics Cache
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.cleaning_services_rounded, color: AppTheme.textSecondary, size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Limpiar Caché de Letras',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Borra todas las letras sincronizadas y planas guardadas offline. Se volverán a descargar automáticamente de internet al reproducir.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.divider),
                      foregroundColor: AppTheme.textPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isScanning ? null : _clearLyricsCache,
                    child: const Text('Limpiar Letras', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(height: 1, color: AppTheme.divider),
              const SizedBox(height: 20),
              // Tool 2: Reset Failed Media
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary, size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Re-intentar Portadas/Letras Fallidas',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Resetea el estado de los archivos que no se encontraron (notFound) para volver a buscarlos con los metadatos limpios o editados.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.divider),
                      foregroundColor: AppTheme.textPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isScanning ? null : _resetFailedMedia,
                    child: const Text('Re-intentar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(height: 1, color: AppTheme.divider),
              const SizedBox(height: 20),
              // Tool 2: Reset DB
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Restablecer Aplicación / Limpiar Biblioteca',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Elimina todas las canciones indexadas, listas de reproducción, géneros y carpetas añadidas. Conserva intactos tus archivos locales de música.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withAlpha(30),
                      foregroundColor: Colors.redAccent,
                      shadowColor: Colors.transparent,
                      side: const BorderSide(color: Colors.redAccent, width: 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isScanning ? null : _resetApplication,
                    child: const Text('Restablecer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
