import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/network/local_sync_client.dart';
import '../../core/network/local_sync_server.dart';
import '../../core/network/orpheus_beacon_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/sync_download_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/sync_progress_panel.dart';

/// Screen and modal view providing discovery, manual connection, and library
/// browsing across Orpheus nodes on the local Wi-Fi / Ethernet network.
class NearbyDevicesView extends StatefulWidget {
  const NearbyDevicesView({
    super.key,
    this.beaconService,
    this.autoStartScan = true,
  });

  final OrpheusBeaconService? beaconService;
  final bool autoStartScan;

  @override
  State<NearbyDevicesView> createState() => _NearbyDevicesViewState();
}

class _NearbyDevicesViewState extends State<NearbyDevicesView> {
  late final OrpheusBeaconService _beacon;
  StreamSubscription<List<DiscoveredNode>>? _nodesSub;
  List<DiscoveredNode> _nodes = [];
  bool _isScanning = false;

  final TextEditingController _ipController = TextEditingController(text: '192.168.1.');
  final TextEditingController _portController = TextEditingController(text: '50505');
  bool _isManualConnecting = false;

  @override
  void initState() {
    super.initState();
    _beacon = widget.beaconService ?? OrpheusBeaconService.instance;
    _nodes = _beacon.activeNodes;
    if (widget.autoStartScan) {
      _startScan();
    } else {
      _nodesSub = _beacon.onNodesChanged.listen((updatedNodes) {
        if (mounted) {
          setState(() {
            _nodes = updatedNodes;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    if (_isScanning) {
      _beacon.stopListening();
    }
    _nodesSub?.cancel();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    try {
      await _beacon.startListening();
      _nodesSub?.cancel();
      _nodesSub = _beacon.onNodesChanged.listen((updatedNodes) {
        if (mounted) {
          setState(() {
            _nodes = updatedNodes;
          });
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleScan() async {
    if (_isScanning) {
      _beacon.stopListening();
      setState(() => _isScanning = false);
    } else {
      await _startScan();
    }
  }

  Future<void> _testPingNode(DiscoveredNode node) async {
    final client = LocalSyncClient.fromNode(node);
    try {
      final ping = await client.pingNode();
      if (!mounted) return;
      AppToast.showText(
        context,
        'Nodo "${ping.deviceName}" conectado (${ping.platform})',
        icon: Icons.check_circle_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.showText(
        context,
        'No se pudo conectar con el nodo: $e',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _connectManualIp() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 50505;

    if (ip.isEmpty) {
      AppToast.showText(context, 'Por favor introduce una dirección IP válida');
      return;
    }

    setState(() => _isManualConnecting = true);
    final baseUrl = 'http://$ip:$port';
    final client = LocalSyncClient(baseUrl: baseUrl);

    try {
      final ping = await client.pingNode();
      if (!mounted) return;
      AppToast.showText(
        context,
        'Conexión exitosa con "${ping.deviceName}"',
        icon: Icons.check_circle_rounded,
      );
      _openRemoteLibraryModal(
        nodeName: ping.deviceName,
        client: client,
      );
    } catch (e) {
      if (!mounted) return;
      AppToast.showText(
        context,
        'Error al conectar con $baseUrl: $e',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) setState(() => _isManualConnecting = false);
    }
  }

  void _openRemoteLibraryModal({
    required String nodeName,
    required LocalSyncClient client,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RemoteLibrarySheet(
        nodeName: nodeName,
        client: client,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        backgroundColor: AppTheme.bgSurface,
        elevation: 0,
        title: const Text(
          'Red Local y Dispositivos',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: AppTheme.textSecondary),
            tooltip: 'Ver descargas offline',
            onPressed: () => SyncProgressPanel.showModal(context),
          ),
          IconButton(
            icon: Icon(
              _isScanning ? Icons.sync_rounded : Icons.sync_disabled_rounded,
              color: _isScanning ? AppTheme.accent : AppTheme.textHint,
            ),
            tooltip: _isScanning ? 'Detener escaneo' : 'Iniciar escaneo',
            onPressed: _toggleScan,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Local Node Host Status Card
          _buildLocalNodeCard(),
          const SizedBox(height: 24),

          // Discovered Nodes Header
          Row(
            children: [
              const Text(
                'Nodos Detectados',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (_isScanning)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
                  ),
                ),
              const Spacer(),
              Text(
                '${_nodes.length} encontrados',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_nodes.isEmpty)
            _buildEmptyState()
          else
            for (final node in _nodes) ...[
              _buildNodeCard(node),
              const SizedBox(height: 12),
            ],

          const SizedBox(height: 28),

          // Manual IP Connection Card
          _buildManualConnectionCard(),
        ],
      ),
    );
  }

  Widget _buildLocalNodeCard() {
    final server = LocalSyncServer.instance;
    final isRunning = server.isRunning;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.computer_rounded,
              color: AppTheme.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        server.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isRunning
                            ? Colors.greenAccent.withValues(alpha: 0.15)
                            : Colors.orangeAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isRunning ? 'SERVIDOR ACTIVO' : 'LOCAL',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isRunning ? Colors.greenAccent : Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isRunning
                      ? 'Puerto ${server.port} • Transmitiendo biblioteca local'
                      : 'Listo para recibir y emitir música en red local',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.wifi_tethering_rounded,
            size: 42,
            color: AppTheme.textHint.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          const Text(
            'Buscando dispositivos en la red...',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Asegúrate de que tus computadoras o teléfonos estén conectados al mismo Wi-Fi con Orpheus abierto.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppTheme.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(DiscoveredNode node) {
    final client = LocalSyncClient.fromNode(node);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _platformIcon(node.platform),
                  color: Colors.cyanAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${node.address.address}:${node.port} • ${node.platform}',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.network_ping_rounded, size: 18),
                tooltip: 'Probar conexión',
                color: AppTheme.textHint,
                onPressed: () => _testPingNode(node),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openRemoteLibraryModal(
                    nodeName: node.deviceName,
                    client: client,
                  ),
                  icon: const Icon(Icons.library_music_rounded, size: 16),
                  label: const Text('Explorar Biblioteca'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.bgDeep,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManualConnectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.router_rounded, color: AppTheme.textSecondary, size: 18),
              SizedBox(width: 8),
              Text(
                'Conexión Directa por IP',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _ipController,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Dirección IP',
                    labelStyle: const TextStyle(color: AppTheme.textHint),
                    filled: true,
                    fillColor: AppTheme.bgHover,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Puerto',
                    labelStyle: const TextStyle(color: AppTheme.textHint),
                    filled: true,
                    fillColor: AppTheme.bgHover,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isManualConnecting ? null : _connectManualIp,
            icon: _isManualConnecting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link_rounded, size: 16),
            label: Text(_isManualConnecting ? 'Conectando...' : 'Conectar al Nodo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.bgHover,
              foregroundColor: AppTheme.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _platformIcon(String platform) {
    final lower = platform.toLowerCase();
    if (lower.contains('linux')) return Icons.laptop_chromebook_rounded;
    if (lower.contains('mac') || lower.contains('darwin')) return Icons.laptop_mac_rounded;
    if (lower.contains('android')) return Icons.phone_android_rounded;
    if (lower.contains('windows')) return Icons.desktop_windows_rounded;
    return Icons.devices_rounded;
  }
}

/// Bottom sheet dialog displaying the remote node's media library with streaming
/// playback and single/bulk download actions.
class _RemoteLibrarySheet extends StatefulWidget {
  const _RemoteLibrarySheet({
    required this.nodeName,
    required this.client,
  });

  final String nodeName;
  final LocalSyncClient client;

  @override
  State<_RemoteLibrarySheet> createState() => _RemoteLibrarySheetState();
}

class _RemoteLibrarySheetState extends State<_RemoteLibrarySheet> {
  bool _isLoading = true;
  String? _error;
  List<Track> _tracks = [];

  @override
  void initState() {
    super.initState();
    _fetchTracks();
  }

  Future<void> _fetchTracks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final fetched = await widget.client.fetchLibrary();
      if (mounted) {
        setState(() {
          _tracks = fetched;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _downloadAll() {
    if (_tracks.isEmpty) return;
    SyncDownloadManager.instance.enqueueTracks(
      _tracks,
      client: widget.client,
    );
    AppToast.showText(
      context,
      'Descargando ${_tracks.length} canciones en segundo plano',
      icon: Icons.download_done_rounded,
    );
  }

  void _downloadSingle(Track track) {
    SyncDownloadManager.instance.enqueueTrack(
      track,
      client: widget.client,
    );
    AppToast.showText(
      context,
      'Descargando "${track.displayTitle}"...',
      icon: Icons.downloading_rounded,
    );
  }

  void _playStream(Track track) {
    AudioPlayerService.instance.loadPlaylist(
      [track],
      initialIndex: 0,
      contextName: 'Streaming Red Local',
    );
    AppToast.showText(
      context,
      'Reproduciendo vía streaming local: ${track.displayTitle}',
      icon: Icons.lan_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.textHint.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Biblioteca de ${widget.nodeName}',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isLoading
                            ? 'Cargando pistas...'
                            : '${_tracks.length} canciones disponibles',
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isLoading && _tracks.isNotEmpty)
                  TextButton.icon(
                    onPressed: _downloadAll,
                    icon: const Icon(Icons.download_for_offline_rounded, size: 16),
                    label: const Text('Descargar Todo'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                    ),
                  ),
              ],
            ),
          ),

          const Divider(color: AppTheme.divider, height: 1),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 36,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Error al obtener biblioteca: $_error',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 14),
                              ElevatedButton(
                                onPressed: _fetchTracks,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _tracks.isEmpty
                        ? const Center(
                            child: Text(
                              'El nodo no tiene pistas indexadas',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _tracks.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: AppTheme.divider, height: 1),
                            itemBuilder: (context, index) {
                              final track = _tracks[index];
                              return ListTile(
                                leading: Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: AppTheme.bgHover,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: track.hasCustomMetadata &&
                                          track.customMetadata.customCoverPath != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.network(
                                            track.customMetadata.customCoverPath!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(
                                              Icons.music_note_rounded,
                                              color: AppTheme.textHint,
                                            ),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.music_note_rounded,
                                          color: AppTheme.textHint,
                                        ),
                                ),
                                title: Text(
                                  track.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  '${track.displayArtist} • ${track.audioQuality}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.play_circle_outline_rounded,
                                        color: Colors.cyanAccent,
                                      ),
                                      tooltip: 'Reproducir stream local',
                                      onPressed: () => _playStream(track),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.download_rounded,
                                        color: AppTheme.textSecondary,
                                      ),
                                      tooltip: 'Descargar para offline',
                                      onPressed: () => _downloadSingle(track),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
