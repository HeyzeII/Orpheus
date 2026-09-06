import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/database/local_database.dart';
import '../../core/models/track.dart';
import '../../core/services/album_art_fetcher_service.dart';
import '../../core/services/audio_handler.dart';
import '../../core/services/audio_scanner.dart';
import '../../core/services/permission_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import 'debug_log_view.dart';

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
  bool _hasFullStorage = true;
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
    final hasFull = await PermissionService.hasFullStorageAccess();
    final config = await LocalDatabase.instance.getConfig();
    final sanitizedDirs = <String>[];
    for (final d in config.scanDirectories) {
      final norm = _normalizePosixPath(d);
      if (norm != null && norm.startsWith('/')) {
        sanitizedDirs.add(norm);
      } else {
        sanitizedDirs.add(d);
      }
    }
    setState(() {
      _hasFullStorage = hasFull;
      _scanDirs = sanitizedDirs;
    });
  }

  /// Normalizes a picked directory path.
  /// If it is a SAF URI (content://), attempts conversion to a native POSIX path.
  /// Returns null if the path is invalid or cannot be represented as POSIX.
  String? _normalizePosixPath(String rawPath) {
    var path = rawPath.trim();
    if (path.isEmpty) return null;

    if (path.startsWith('/')) {
      return path;
    }

    if (path.startsWith('content://')) {
      try {
        final decoded = Uri.decodeFull(path);

        // Pattern 1: primary storage (internal)
        if (decoded.contains('primary:')) {
          final subPath = decoded.split('primary:').last;
          final cleanSub = subPath.replaceFirst(RegExp(r'^/+'), '');
          return cleanSub.isEmpty
              ? '/storage/emulated/0'
              : '/storage/emulated/0/$cleanSub';
        }

        // Pattern 2: SD card UUID (e.g. 1234-5678:Music)
        final uuidMatch =
            RegExp(r'([0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}):(.*)').firstMatch(decoded);
        if (uuidMatch != null) {
          final uuid = uuidMatch.group(1);
          final subPath =
              (uuidMatch.group(2) ?? '').replaceFirst(RegExp(r'^/+'), '');
          return subPath.isEmpty ? '/storage/$uuid' : '/storage/$uuid/$subPath';
        }
      } catch (e) {
        debugPrint('Error decodificando URI SAF ($path): $e');
      }
    }

    return null;
  }

  /// Checks if the app has full storage access. If not, shows an explanation dialog
  /// offering to redirect to Android system settings.
  Future<bool> _ensureFullStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final hasFull = await PermissionService.hasFullStorageAccess();
    if (hasFull) {
      if (!_hasFullStorage) setState(() => _hasFullStorage = true);
      return true;
    }

    if (!mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.divider),
        ),
        title: const Row(
          children: [
            Icon(Icons.folder_special_rounded, color: AppTheme.accent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Acceso a todos los archivos',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Android requiere que habilites "Acceso a todos los archivos" para que Orpheus pueda descubrir la totalidad de tus canciones en el almacenamiento.\n\n'
          'Sin este permiso, el sistema operativo restringirá el escáner a una cantidad reducida de archivos indexados.\n\n'
          '¿Deseas habilitarlo ahora en los Ajustes del sistema?',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Omitir',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.bgDeep,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Abrir Ajustes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await PermissionService.openManageAllFilesAccess();
      final refreshed = await PermissionService.hasFullStorageAccess();
      setState(() => _hasFullStorage = refreshed);
      return refreshed;
    }

    return false;
  }

  Future<void> _addDirectory() async {
    final hasFull = await _ensureFullStoragePermission();
    if (!hasFull) {
      final grantedBasic = await PermissionService.requestStoragePermission();
      if (!grantedBasic) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Se requieren permisos de almacenamiento para escanear música.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    final rawPath = await FilePicker.platform.getDirectoryPath();
    if (rawPath == null) return;

    final normalizedPath = _normalizePosixPath(rawPath);
    if (normalizedPath == null || !normalizedPath.startsWith('/')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ruta no compatible ($rawPath). Selecciona una carpeta desde el almacenamiento interno.',
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    await LocalDatabase.instance.addScanDirectory(normalizedPath);
    await _loadConfig();
  }

  Future<void> _removeDirectory(String path) async {
    await LocalDatabase.instance.removeScanDirectory(path);
    await _loadConfig();
  }

  Future<void> _runScan() async {
    if (_scanDirs.isEmpty) return;

    final hasFull = await PermissionService.hasFullStorageAccess();
    if (!hasFull) {
      final granted = await _ensureFullStoragePermission();
      if (!granted && mounted) {
        AppToast.showText(
          context,
          'Aviso: Sin acceso a todos los archivos, el escaneo solo detectará pistas pre-indexadas.',
          icon: Icons.warning_amber_rounded,
        );
      }
    }

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
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return StreamBuilder<Track?>(
      stream: OrpheusAudioHandler.instance.currentTrackStream,
      initialData: OrpheusAudioHandler.instance.currentTrack,
      builder: (context, snap) {
        final hasTrack = snap.data != null && snap.data!.trackId.isNotEmpty;
        final sysPad = MediaQuery.of(context).padding.bottom;
        // Panel = nav bar (60) + gap (12). If mini-player visible, add 64px.
        final bottomPad = isMobile
            ? (hasTrack ? 60.0 + 64.0 + 12.0 : 60.0 + 12.0) + sysPad + 16.0
            : 32.0;
        final hPad = isMobile ? 16.0 : 32.0;
        final tPad = isMobile ? (MediaQuery.of(context).padding.top + 16.0) : 36.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(hPad, tPad, hPad, bottomPad),
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

          // ── Storage Permission Warning Banner ──────────────────────────────
          _buildStoragePermissionBanner(),

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
      },
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

  Widget _buildStoragePermissionBanner() {
    if (_hasFullStorage || !Platform.isAndroid) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withAlpha(50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.amberAccent, size: 24),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Acceso total a archivos inactivo',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Para detectar los 425+ archivos de tu biblioteca, activa "Acceso a todos los archivos" en Ajustes.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () async {
              await PermissionService.openManageAllFilesAccess();
              final has = await PermissionService.hasFullStorageAccess();
              setState(() => _hasFullStorage = has);
            },
            child: const Text('Activar',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
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
            // 2×2 KPI grid — clean, spacious, readable on both desktop and mobile.
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.4,
              ),
              children: [
                _buildKpiCard('Procesados', _scannedCount, Icons.folder_open_rounded),
                _buildKpiCard('Agregados', _addedCount, Icons.add_circle_outline_rounded),
                _buildKpiCard('Actualizados', _updatedCount, Icons.sync_rounded),
                _buildKpiCard('Ignorados / Error', _skippedCount, Icons.block_rounded, isError: true),
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

  Widget _buildKpiCard(String label, int value, IconData icon, {bool isError = false}) {
    final numColor = isError && value > 0 ? Colors.redAccent : AppTheme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: numColor, size: 22),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: numColor,
                  fontFamily: 'Inter',
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ],
      ),
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
    await OrpheusAudioHandler.instance.stopAndReset();
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

  Future<void> _runNotificationDiagnostics() async {
    try {
      const channel = MethodChannel('com.heyzell.orpheus/app_control');
      final Map<dynamic, dynamic>? result =
          await channel.invokeMethod<Map<dynamic, dynamic>>('getNotificationDiagnostics');
      
      if (result == null) {
        if (!mounted) return;
        AppToast.showText(context, 'No se pudo obtener el diagnóstico nativo.', icon: Icons.error_outline);
        return;
      }

      final report = Map<String, dynamic>.from(result);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppTheme.bgSurface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppTheme.divider),
            ),
            title: Row(
              children: [
                const Icon(Icons.analytics_rounded, color: AppTheme.accent),
                const SizedBox(width: 10),
                const Text(
                  'Auditoría de Audio',
                  style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('1. CANAL DE NOTIFICACIONES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  Text('• Permisos habilitados (DND/Gral): ${report['areNotificationsEnabled'] ?? 'Desconocido'}'),
                  Text('• Canal existe: ${report['channelExists'] ?? 'No'}'),
                  if (report['channelExists'] == true) ...[
                    Text('  - ID Canal: ${report['channelId']}'),
                    Text('  - Nombre: ${report['channelName']}'),
                    Text('  - Importancia: ${report['channelImportance']} (Default: 3, Low: 2)'),
                    Text('  - Visibilidad lockscreen: ${report['channelLockscreenVisibility']} (Public: 1)'),
                    Text('  - Ignorar DND (canBypassDnd): ${report['channelBypassDnd']}'),
                    Text('  - Mostrar punto: ${report['channelShowBadge']}'),
                  ],
                  const SizedBox(height: 16),
                  const Text('2. SERVICIO EN PRIMER PLANO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  Text('• Servicio corriendo (AudioService): ${report['serviceRunning'] ?? 'No'}'),
                  if (report['serviceError'] != null)
                    Text('  - Error: ${report['serviceError']}', style: const TextStyle(color: Colors.redAccent)),
                  if (report['serviceRunning'] == true) ...[
                    Text('  - Estado reproducción: ${report['serviceProcessingState']}'),
                    Text('  - Reproduciendo (playing): ${report['servicePlaying']}'),
                    Text('  - Creado en cortina (notificationCreated): ${report['notificationCreated']}'),
                    Text('  - Canal usado por servicio: ${report['serviceNotificationChannelId']}'),
                  ],
                  const SizedBox(height: 16),
                  const Text('3. MEDIASESSION Y METADATOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 6),
                  if (report['serviceRunning'] == true) ...[
                    Text('• MediaSession Activo: ${report['mediaSessionActive'] ?? 'Desconocido'}'),
                    Text('• Metadatos cargados: ${report['metadataLoaded'] ?? 'No'}'),
                    if (report['metadataLoaded'] == true) ...[
                      Text('  - Título: ${report['metadataTitle']}'),
                      Text('  - Artista: ${report['metadataArtist']}'),
                    ],
                    Text('• Portada cargada (artBitmap): ${report['artBitmapLoaded'] ?? 'No'}'),
                    if (report['artBitmapLoaded'] == true)
                      Text('  - Dimensiones: ${report['artBitmapWidth']}x${report['artBitmapHeight']} px'),
                  ] else ...[
                    const Text('El servicio de reproducción no está activo en este momento. Reproduce una canción antes de auditar.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textSecondary)),
                  ],
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.bgDeep,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.showText(context, 'Error al ejecutar auditoría: $e', icon: Icons.error_outline);
    }
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
              // Tool 3: Notification & Audio Diagnostics
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.analytics_outlined, color: AppTheme.accent, size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Auditoría de Audio y Notificaciones',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ejecuta un diagnóstico en tiempo de ejecución de los canales de notificación nativos, el estado del servicio en primer plano y MediaSession.',
                          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.divider),
                      foregroundColor: AppTheme.textPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isScanning ? null : _runNotificationDiagnostics,
                    child: const Text('Auditar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DebugLogScreen()),
                      );
                    },
                    child: const Text('Ver Logs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(height: 1, color: AppTheme.divider),
              const SizedBox(height: 20),
              // Tool 4: Reset DB
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
