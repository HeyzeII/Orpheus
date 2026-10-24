import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/models/track.dart';
import '../../core/network/local_sync_client.dart';
import '../../core/network/orpheus_beacon_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/sync_download_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/track_cover_art.dart';
import '../widgets/video_badge.dart';

/// Helper grouping for albums in the remote catalog.
class _RemoteAlbumGroup {
  final String albumName;
  final String artistName;
  final String? coverUrl;
  final List<Track> tracks;

  const _RemoteAlbumGroup({
    required this.albumName,
    required this.artistName,
    required this.coverUrl,
    required this.tracks,
  });
}

/// Helper grouping for artists in the remote catalog.
class _RemoteArtistGroup {
  final String artistName;
  final List<Track> tracks;
  final int albumCount;

  const _RemoteArtistGroup({
    required this.artistName,
    required this.tracks,
    required this.albumCount,
  });
}

/// Modo Nexus — Tidal-style Remote Library View for exploring, streaming,
/// and downloading media across discovered Orpheus peers on the local network.
class NexusView extends StatefulWidget {
  const NexusView({
    super.key,
    this.beaconService,
    this.syncClient,
    this.database,
    this.downloadManager,
  });

  final OrpheusBeaconService? beaconService;
  final LocalSyncClient? syncClient;
  final LocalDatabase? database;
  final SyncDownloadManager? downloadManager;

  @override
  State<NexusView> createState() => _NexusViewState();
}

/// Sort modes for the remote catalog.
enum _NexusSortMode { title, artist, duration, downloadedFirst }

class _NexusViewState extends State<NexusView> with SingleTickerProviderStateMixin {
  late final OrpheusBeaconService _beacon;
  late final LocalDatabase _db;
  late final SyncDownloadManager _downloadMgr;

  StreamSubscription<List<DiscoveredNode>>? _beaconSub;
  StreamSubscription<SyncDownloadTask>? _downloadSub;
  StreamSubscription<void>? _dbSub;

  List<DiscoveredNode> _nodes = [];
  DiscoveredNode? _selectedNode;
  bool _isNodeDisconnected = false;

  bool _isLoadingCatalog = false;
  String? _catalogError;
  List<Track> _catalogTracks = [];
  Set<String> _localDownloadedTrackIds = {};

  // Per-node catalog cache: avoids re-fetching when switching back to a node.
  final Map<String, List<Track>> _catalogCache = {};

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _selectedSubTab = 0; // 0: Canciones, 1: Álbumes, 2: Artistas, 3: Videos

  _NexusSortMode _sortMode = _NexusSortMode.title;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _beacon = widget.beaconService ?? OrpheusBeaconService.instance;
    _db = widget.database ?? LocalDatabase.instance;
    _downloadMgr = widget.downloadManager ?? SyncDownloadManager.instance;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _nodes = _beacon.activeNodes;
    if (_nodes.isNotEmpty) {
      _selectedNode = _nodes.first;
    }

    _beaconSub = _beacon.onNodesChanged.listen(_onNodesChanged);
    _downloadSub = _downloadMgr.onTaskUpdated.listen((_) => _refreshLocalDownloadedIds());
    _dbSub = _db.watchTracks().listen((_) => _refreshLocalDownloadedIds());

    _refreshLocalDownloadedIds();

    if (_selectedNode != null) {
      _loadCatalog();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _beaconSub?.cancel();
    _downloadSub?.cancel();
    _dbSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onNodesChanged(List<DiscoveredNode> updatedNodes) {
    if (!mounted) return;
    setState(() {
      _nodes = updatedNodes;

      if (_selectedNode != null) {
        final stillAlive = updatedNodes.any(
          (n) => n.deviceId == _selectedNode!.deviceId || n.baseUrl == _selectedNode!.baseUrl,
        );
        _isNodeDisconnected = !stillAlive;
      } else if (updatedNodes.isNotEmpty) {
        _selectedNode = updatedNodes.first;
        _isNodeDisconnected = false;
        _loadCatalog();
      }
    });
  }

  Future<void> _refreshLocalDownloadedIds() async {
    try {
      final localTracks = await _db.getAllTracks();
      final downloaded = <String>{};
      for (final t in localTracks) {
        if (!AudioPlayerService.isRemoteUri(t.filePath)) {
          downloaded.add(t.trackId);
        }
      }
      if (mounted) {
        setState(() {
          _localDownloadedTrackIds = downloaded;
        });
      }
    } catch (_) {}
  }

  bool _isTrackDownloaded(String trackId) {
    if (_localDownloadedTrackIds.contains(trackId)) return true;
    final task = _downloadMgr.getTask(trackId);
    return task?.status == SyncDownloadStatus.completed;
  }

  Future<void> _selectNode(DiscoveredNode node) async {
    if (_selectedNode?.deviceId == node.deviceId &&
        _selectedNode?.baseUrl == node.baseUrl &&
        _catalogTracks.isNotEmpty &&
        !_isNodeDisconnected) {
      return;
    }

    setState(() {
      _selectedNode = node;
      _isNodeDisconnected = false;
    });

    await _loadCatalog();
  }

  Future<void> _loadCatalog({bool forceRefresh = false}) async {
    if (_selectedNode == null) return;

    final cacheKey = _selectedNode!.deviceId.isNotEmpty
        ? _selectedNode!.deviceId
        : _selectedNode!.baseUrl;

    // Serve from cache if available and not a forced refresh.
    if (!forceRefresh && _catalogCache.containsKey(cacheKey)) {
      if (mounted) {
        setState(() {
          _catalogTracks = _catalogCache[cacheKey]!;
          _isLoadingCatalog = false;
          _catalogError = null;
        });
      }
      return;
    }

    setState(() {
      _isLoadingCatalog = true;
      _catalogError = null;
    });

    try {
      final client = widget.syncClient ?? LocalSyncClient.fromNode(_selectedNode!);
      final tracks = await client.fetchLibrary();

      _catalogCache[cacheKey] = tracks;

      if (mounted) {
        setState(() {
          _catalogTracks = tracks;
          _isLoadingCatalog = false;
          _isNodeDisconnected = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCatalog = false;
          _catalogError = e.toString();
          // Serve stale cache if we have it so UI doesn't go blank
          if (_catalogCache.containsKey(cacheKey)) {
            _catalogTracks = _catalogCache[cacheKey]!;
          }
          final stillAlive = _beacon.activeNodes.any(
            (n) => n.deviceId == _selectedNode!.deviceId || n.baseUrl == _selectedNode!.baseUrl,
          );
          if (!stillAlive) {
            _isNodeDisconnected = true;
          }
        });
      }
    }
  }

  void _downloadTrack(Track track) {
    if (_selectedNode == null) return;
    final client = widget.syncClient ?? LocalSyncClient.fromNode(_selectedNode!);
    _downloadMgr.enqueueTrack(track, client: client);
    AppToast.showText(
      context,
      'Descargando "${track.displayTitle}"...',
      icon: Icons.downloading_rounded,
    );
  }

  void _downloadAllFiltered() {
    if (_selectedNode == null) return;
    final toDownload = _filteredTracks.where((t) => !_isTrackDownloaded(t.trackId)).toList();
    if (toDownload.isEmpty) {
      AppToast.showText(context, 'Todas las canciones ya están descargadas');
      return;
    }

    final client = widget.syncClient ?? LocalSyncClient.fromNode(_selectedNode!);
    _downloadMgr.enqueueTracks(toDownload, client: client);
    AppToast.showText(
      context,
      'Descargando ${toDownload.length} canciones en segundo plano',
      icon: Icons.download_done_rounded,
    );
  }

  void _playTrack(Track track, int index) {
    final isDownloaded = _isTrackDownloaded(track.trackId);

    if (!isDownloaded && _isNodeDisconnected) {
      AppToast.showText(
        context,
        'Nodo desconectado. Conéctate a la misma red Wi-Fi para reproducir vía streaming.',
        icon: Icons.wifi_off_rounded,
      );
      return;
    }

    final tracksToPlay = _filteredTracks;
    AudioPlayerService.instance.loadPlaylist(
      tracksToPlay,
      initialIndex: index,
      contextName: 'Nexus: ${_selectedNode?.deviceName ?? "Remoto"}',
    );

    AppToast.showText(
      context,
      isDownloaded
          ? 'Reproduciendo: ${track.displayTitle}'
          : 'Streaming desde ${_selectedNode?.deviceName ?? "nodo"}: ${track.displayTitle}',
      icon: isDownloaded ? Icons.play_arrow_rounded : Icons.wifi_tethering_rounded,
    );
  }

  // ── Filters, Sort & Groups ─────────────────────────────────────────────────

  List<Track> get _filteredTracks {
    List<Track> result = _catalogTracks;

    if (_searchQuery.isNotEmpty) {
      result = result.where((t) {
        final title = t.displayTitle.toLowerCase();
        final artist = t.displayArtist.toLowerCase();
        final album = t.displayAlbum.toLowerCase();
        return title.contains(_searchQuery) ||
            artist.contains(_searchQuery) ||
            album.contains(_searchQuery);
      }).toList();
    }

    // Apply sort
    switch (_sortMode) {
      case _NexusSortMode.title:
        result = List.of(result)..sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
      case _NexusSortMode.artist:
        result = List.of(result)..sort((a, b) => a.displayArtist.compareTo(b.displayArtist));
      case _NexusSortMode.duration:
        result = List.of(result)..sort((a, b) => a.duration.compareTo(b.duration));
      case _NexusSortMode.downloadedFirst:
        result = List.of(result)..sort((a, b) {
          final aD = _isTrackDownloaded(a.trackId) ? 0 : 1;
          final bD = _isTrackDownloaded(b.trackId) ? 0 : 1;
          if (aD != bD) return aD.compareTo(bD);
          return a.displayTitle.compareTo(b.displayTitle);
        });
    }

    return result;
  }

  List<_RemoteAlbumGroup> get _filteredAlbums {
    final audioTracks = _filteredTracks.where((t) => !t.isVideo).toList();
    final Map<String, List<Track>> groups = {};

    for (final t in audioTracks) {
      final alb = t.displayAlbum;
      groups.putIfAbsent(alb, () => []).add(t);
    }

    return groups.entries.map((entry) {
      final first = entry.value.first;
      return _RemoteAlbumGroup(
        albumName: entry.key,
        artistName: first.displayArtist,
        coverUrl: first.customMetadata.customCoverPath,
        tracks: entry.value,
      );
    }).toList();
  }

  List<_RemoteArtistGroup> get _filteredArtists {
    final Map<String, List<Track>> groups = {};

    for (final t in _filteredTracks) {
      final art = t.displayArtist;
      groups.putIfAbsent(art, () => []).add(t);
    }

    return groups.entries.map((entry) {
      final albums = entry.value.map((t) => t.displayAlbum).toSet().length;
      return _RemoteArtistGroup(
        artistName: entry.key,
        tracks: entry.value,
        albumCount: albums,
      );
    }).toList();
  }

  List<Track> get _filteredVideos {
    return _filteredTracks.where((t) => t.isVideo).toList();
  }

  IconData _platformIcon(String platform) {
    final lower = platform.toLowerCase();
    if (lower.contains('mac') || lower.contains('darwin')) return Icons.laptop_mac_rounded;
    if (lower.contains('android')) return Icons.phone_android_rounded;
    if (lower.contains('linux')) return Icons.laptop_chromebook_rounded;
    if (lower.contains('windows')) return Icons.desktop_windows_rounded;
    return Icons.devices_rounded;
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. Nexus Header & Node Selector
            _buildNexusHeader(isMobile),

            // 2. Disconnect Banner (if node is offline)
            if (_isNodeDisconnected && _selectedNode != null)
              _buildDisconnectBanner(),

            // 3. Search & Subtabs Bar — always visible when a node is selected
            if (_selectedNode != null)
              _buildControlsBar(isMobile),

            // 4. Main Body Content
            Expanded(
              child: _buildBody(isMobile),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header & Node Selector ─────────────────────────────────────────────────

  Widget _buildNexusHeader(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface.withOpacity(0.5),
        border: const Border(
          bottom: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accent,
                      AppTheme.accent.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.hub_rounded,
                  color: AppTheme.bgDeep,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'MODO NEXUS',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppTheme.accent.withOpacity(0.4),
                              width: 0.8,
                            ),
                          ),
                          child: const Text(
                            'RED LOCAL',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Explora, transmite y sincroniza el catálogo de tus dispositivos en red',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11.5,
                        color: AppTheme.textSecondary.withOpacity(0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.sync_rounded, color: AppTheme.textSecondary, size: 22),
                tooltip: 'Buscar nuevos nodos',
                onPressed: () {
                  _beacon.resume();
                  _loadCatalog(forceRefresh: true);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildNodeSelectorPills(),
        ],
      ),
    );
  }

  Widget _buildNodeSelectorPills() {
    if (_nodes.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgHover.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withOpacity(0.4 + _pulseCtrl.value * 0.6),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withOpacity(_pulseCtrl.value * 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Buscando nodos Orpheus en tu red Wi-Fi...',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                _beacon.resume();
              },
              child: const Text('Reintentar', style: TextStyle(color: AppTheme.accent, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _nodes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          final node = _nodes[idx];
          final isSelected = _selectedNode?.deviceId == node.deviceId;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _selectNode(node),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.accent.withOpacity(0.18) : AppTheme.bgHover,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppTheme.accent : AppTheme.divider,
                    width: isSelected ? 1.4 : 1.0,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppTheme.accent.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _platformIcon(node.platform),
                      size: 16,
                      color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      node.deviceName,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981), // Emerald green online dot
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Disconnect Banner ──────────────────────────────────────────────────────

  Widget _buildDisconnectBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF451A03).withOpacity(0.85), // Deep amber dark
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF59E0B), width: 1.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFFBBF24),
            size: 20,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Nodo desconectado — Mostrando contenido disponible. El streaming en vivo está pausado.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Color(0xFFFEF3C7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              _beacon.resume();
              _loadCatalog();
            },
            child: const Text(
              'Reconectar',
              style: TextStyle(
                color: Color(0xFFFBBF24),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shimmer Skeleton Loader ─────────────────────────────────────────────────

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: 8,
      itemBuilder: (context, idx) => _SkeletonTile(delay: idx * 60),
    );
  }

  // ── Search & Controls Bar ──────────────────────────────────────────────────

  Widget _buildControlsBar(bool isMobile) {
    final hasCatalog = _catalogTracks.isNotEmpty;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 24,
        vertical: 10,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Search + Sort + Download row
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.bgHover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    enabled: hasCatalog,
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: _isLoadingCatalog
                          ? 'Cargando catálogo...'
                          : 'Buscar en canciones, álbumes y artistas...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.textHint),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16, color: AppTheme.textHint),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
              ),
              if (hasCatalog) ...[
                const SizedBox(width: 8),
                // Sort dropdown
                Tooltip(
                  message: 'Ordenar catálogo',
                  child: PopupMenuButton<_NexusSortMode>(
                    initialValue: _sortMode,
                    onSelected: (mode) => setState(() => _sortMode = mode),
                    color: AppTheme.bgSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppTheme.divider),
                    ),
                    itemBuilder: (_) => [
                      _sortItem(_NexusSortMode.title, 'Por título', Icons.sort_by_alpha_rounded),
                      _sortItem(_NexusSortMode.artist, 'Por artista', Icons.person_rounded),
                      _sortItem(_NexusSortMode.duration, 'Por duración', Icons.timer_outlined),
                      _sortItem(_NexusSortMode.downloadedFirst, 'Descargadas primero', Icons.download_done_rounded),
                    ],
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.bgHover,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_vert_rounded, size: 16, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            _sortModeLabel(_sortMode),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.bgDeep,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.download_for_offline_rounded, size: 16),
                  label: Text(
                    isMobile ? 'Descargar' : 'Descargar Todo',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onPressed: _downloadAllFiltered,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Subtabs row
          Row(
            children: [
              _buildSubTab(0, 'Canciones', _filteredTracks.length),
              const SizedBox(width: 6),
              _buildSubTab(1, 'Álbumes', _filteredAlbums.length),
              const SizedBox(width: 6),
              _buildSubTab(2, 'Artistas', _filteredArtists.length),
              const SizedBox(width: 6),
              _buildSubTab(3, 'Videos', _filteredVideos.length),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_NexusSortMode> _sortItem(
    _NexusSortMode mode,
    String label,
    IconData icon,
  ) {
    final active = _sortMode == mode;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 16,
              color: active ? AppTheme.accent : AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: active ? AppTheme.accent : AppTheme.textPrimary,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 6),
            const Icon(Icons.check_rounded, size: 14, color: AppTheme.accent),
          ],
        ],
      ),
    );
  }

  String _sortModeLabel(_NexusSortMode mode) {
    switch (mode) {
      case _NexusSortMode.title: return 'Título';
      case _NexusSortMode.artist: return 'Artista';
      case _NexusSortMode.duration: return 'Duración';
      case _NexusSortMode.downloadedFirst: return 'Descargadas';
    }
  }

  Widget _buildSubTab(int index, String title, int count) {
    final active = _selectedSubTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedSubTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.accent.withOpacity(0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(color: AppTheme.accent.withOpacity(0.4), width: 1)
              : Border.all(color: Colors.transparent, width: 1),
        ),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppTheme.accent : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: active ? AppTheme.accent.withOpacity(0.8) : AppTheme.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Body Views ─────────────────────────────────────────────────────────────

  Widget _buildBody(bool isMobile) {
    if (_nodes.isEmpty && _selectedNode == null) {
      return _buildNoNodesState();
    }

    // Show skeleton shimmer while loading (instead of a plain spinner)
    if (_isLoadingCatalog && _catalogTracks.isEmpty) {
      return _buildSkeletonLoader();
    }

    if (_catalogError != null && _catalogTracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFEF4444)),
              const SizedBox(height: 16),
              const Text(
                'No se pudo conectar con el nodo',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _catalogError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.bgDeep,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
                onPressed: _loadCatalog,
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredTracks.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty
              ? 'No se encontraron resultados para "$_searchQuery"'
              : 'El catálogo del nodo está vacío',
          style: const TextStyle(color: AppTheme.textHint, fontSize: 13),
        ),
      );
    }

    return switch (_selectedSubTab) {
      0 => _buildSongsList(isMobile),
      1 => _buildAlbumsGrid(isMobile),
      2 => _buildArtistsList(isMobile),
      3 => _buildVideosList(isMobile),
      _ => _buildSongsList(isMobile),
    };
  }

  Widget _buildNoNodesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.bgHover,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.divider),
              ),
              child: const Icon(
                Icons.wifi_tethering_rounded,
                size: 38,
                color: AppTheme.textHint,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No se detectaron dispositivos en red',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Abre Orpheus en tu computadora o teléfono conectado a la misma red local Wi-Fi para explorar y transmitir música sin cables.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.radar_rounded, size: 18),
              label: const Text(
                'Escanear Red Local',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () {
                _beacon.resume();
                _refreshLocalDownloadedIds();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Subtab 0: Canciones ────────────────────────────────────────────────────

  Widget _buildSongsList(bool isMobile) {
    final tracks = _filteredTracks;

    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: AppTheme.bgSurface,
      onRefresh: () => _loadCatalog(forceRefresh: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isMobile ? 12 : 20,
          12,
          isMobile ? 12 : 20,
          isMobile ? 120 : 100,
        ),
        itemCount: tracks.length,
        itemBuilder: (context, idx) {
          final track = tracks[idx];
          final isDownloaded = _isTrackDownloaded(track.trackId);

          return _buildTrackTile(
            track: track,
            index: idx,
            isDownloaded: isDownloaded,
            onTap: () => _playTrack(track, idx),
            onDownload: () => _downloadTrack(track),
          );
        },
      ),
    );
  }

  Widget _buildTrackTile({
    required Track track,
    required int index,
    required bool isDownloaded,
    required VoidCallback onTap,
    required VoidCallback onDownload,
  }) {
    final double contentOpacity = isDownloaded ? 1.0 : 0.55;

    return StreamBuilder<SyncDownloadTask?>(
      // Rebuild only when this track's download task emits an update.
      stream: _downloadMgr.onTaskUpdated
          .where((t) => t.trackId == track.trackId)
          .map<SyncDownloadTask?>((t) => t)
          .distinct(),
      initialData: _downloadMgr.getTask(track.trackId),
      builder: (context, taskSnap) {
        final task = taskSnap.data;
        final isDownloading = task != null && task.isRunning;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              hoverColor: AppTheme.bgHover,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Track Cover Art
                        TrackCoverArt(
                          coverPath: track.customMetadata.customCoverPath,
                          width: 44,
                          height: 44,
                          borderRadius: BorderRadius.circular(6),
                          cacheWidth: 88,
                          fallbackIconSize: 20,
                        ),
                        const SizedBox(width: 14),

                        // Title + Subtitle with dynamic opacity
                        Expanded(
                          child: Opacity(
                            opacity: contentOpacity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        track.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (track.isVideo) ...[
                                      const SizedBox(width: 6),
                                      const VideoBadge(compact: true),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${track.displayArtist} • ${track.displayAlbum}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11.5,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Duration
                        Text(
                          _formatDuration(track.duration),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppTheme.textHint.withOpacity(contentOpacity),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Status indicator: downloaded / downloading (with %) / streaming
                        if (isDownloaded)
                          Tooltip(
                            message: 'Descargado localmente',
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withOpacity(0.16),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.accent,
                                size: 18,
                              ),
                            ),
                          )
                        else if (isDownloading)
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: task.progress > 0 ? task.progress : null,
                                  strokeWidth: 2.0,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                                  backgroundColor: AppTheme.divider,
                                ),
                                Text(
                                  task.progress > 0
                                      ? '${task.percentage}'
                                      : '…',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 8,
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: 'Disponible vía streaming local',
                                child: Icon(
                                  Icons.wifi_tethering_rounded,
                                  color: AppTheme.textHint.withOpacity(0.7),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.download_rounded, size: 20),
                                color: AppTheme.accent,
                                tooltip: 'Descargar canción',
                                onPressed: onDownload,
                              ),
                            ],
                          ),
                      ],
                    ),
                    // Inline download progress bar + speed
                    if (isDownloading && task.progress > 0) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 58),
                        child: Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: task.progress,
                                  minHeight: 2.5,
                                  backgroundColor: AppTheme.divider,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              task.formattedSpeed,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 9.5,
                                color: AppTheme.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Subtab 1: Álbumes ──────────────────────────────────────────────────────

  Widget _buildAlbumsGrid(bool isMobile) {
    final albums = _filteredAlbums;

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        16,
        isMobile ? 12 : 24,
        isMobile ? 120 : 100,
      ),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: isMobile ? 180 : 210,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.74,
      ),
      itemCount: albums.length,
      itemBuilder: (context, idx) {
        final album = albums[idx];
        final allDownloaded = album.tracks.every((t) => _isTrackDownloaded(t.trackId));

        return GestureDetector(
          onTap: () => _showAlbumDetailModal(album),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.divider),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: TrackCoverArt(
                      coverPath: album.coverUrl,
                      borderRadius: BorderRadius.circular(8),
                      cacheWidth: 320,
                      fallbackIcon: Icons.album_rounded,
                      fallbackIconSize: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        album.albumName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (allDownloaded)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppTheme.accent,
                        size: 14,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  album.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${album.tracks.length} canciones',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 10.5,
                    color: AppTheme.textHint,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAlbumDetailModal(_RemoteAlbumGroup album) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollCtrl) {
            return Column(
              children: [
                // Modal Handle
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Album Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      TrackCoverArt(
                        coverPath: album.coverUrl,
                        width: 72,
                        height: 72,
                        borderRadius: BorderRadius.circular(10),
                        cacheWidth: 150,
                        fallbackIcon: Icons.album_rounded,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.albumName,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              album.artistName,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${album.tracks.length} canciones',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: AppTheme.textHint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_for_offline_rounded, color: AppTheme.accent),
                        tooltip: 'Descargar todo el disco',
                        onPressed: () {
                          Navigator.pop(context);
                          if (_selectedNode == null) return;
                          final client = widget.syncClient ?? LocalSyncClient.fromNode(_selectedNode!);
                          _downloadMgr.enqueueTracks(album.tracks, client: client);
                          AppToast.showText(
                            this.context,
                            'Descargando "${album.albumName}"...',
                            icon: Icons.download_done_rounded,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.divider),
                // Tracks in album
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: album.tracks.length,
                    itemBuilder: (context, idx) {
                      final t = album.tracks[idx];
                      final isDownloaded = _isTrackDownloaded(t.trackId);
                      return _buildTrackTile(
                        track: t,
                        index: idx,
                        isDownloaded: isDownloaded,
                        onTap: () {
                          Navigator.pop(context);
                          _playTrack(t, idx);
                        },
                        onDownload: () => _downloadTrack(t),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Subtab 2: Artistas ─────────────────────────────────────────────────────

  Widget _buildArtistsList(bool isMobile) {
    final artists = _filteredArtists;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        14,
        isMobile ? 12 : 24,
        isMobile ? 120 : 100,
      ),
      itemCount: artists.length,
      itemBuilder: (context, idx) {
        final artist = artists[idx];

        return ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          hoverColor: AppTheme.bgHover,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.accent.withOpacity(0.35)),
            ),
            child: Center(
              child: Text(
                artist.artistName.isNotEmpty ? artist.artistName[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
          title: Text(
            artist.artistName,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            '${artist.tracks.length} canciones • ${artist.albumCount} álbumes',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
          onTap: () {
            // Filter by this artist in real time
            _searchCtrl.text = artist.artistName;
            setState(() {
              _searchQuery = artist.artistName.toLowerCase();
              _selectedSubTab = 0; // jump to songs
            });
          },
        );
      },
    );
  }

  // ── Subtab 3: Videos ───────────────────────────────────────────────────────

  Widget _buildVideosList(bool isMobile) {
    final videos = _filteredVideos;

    if (videos.isEmpty) {
      return const Center(
        child: Text(
          'El nodo remoto no tiene videoclips compartidos',
          style: TextStyle(color: AppTheme.textHint, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 12 : 20,
        14,
        isMobile ? 12 : 20,
        isMobile ? 120 : 100,
      ),
      itemCount: videos.length,
      itemBuilder: (context, idx) {
        final track = videos[idx];
        final isDownloaded = _isTrackDownloaded(track.trackId);

        return _buildTrackTile(
          track: track,
          index: idx,
          isDownloaded: isDownloaded,
          onTap: () => _playTrack(track, idx),
          onDownload: () => _downloadTrack(track),
        );
      },
    );
  }
}

// ── Shimmer Skeleton Tile ─────────────────────────────────────────────────────

/// Animates a single skeleton placeholder tile with a shimmer sweep.
class _SkeletonTile extends StatefulWidget {
  const _SkeletonTile({this.delay = 0});
  final int delay; // ms delay before animation starts

  @override
  State<_SkeletonTile> createState() => _SkeletonTileState();
}

class _SkeletonTileState extends State<_SkeletonTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: AnimatedBuilder(
        animation: _shimmer,
        builder: (_, __) {
          final gradient = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0xFF1E1E2E),
              Color(0xFF2E2E42),
              Color(0xFF1E1E2E),
            ],
            stops: [
              (_shimmer.value - 0.3).clamp(0.0, 1.0),
              _shimmer.value.clamp(0.0, 1.0),
              (_shimmer.value + 0.3).clamp(0.0, 1.0),
            ],
          );
          return Row(
            children: [
              // Cover placeholder
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 14),
              // Text placeholders
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 13,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      height: 11,
                      width: 160,
                      decoration: BoxDecoration(
                        gradient: gradient,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Duration placeholder
              Container(
                width: 34,
                height: 11,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
