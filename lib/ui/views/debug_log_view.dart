import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/utils/debug_logger.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// Interactive telemetry viewer screen for inspecting real-time AudioService logs.
class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _copyToClipboard(BuildContext context) {
    final logs = DebugLogger.getAllLogs();
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay logs para copiar.')),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: logs)).then((_) {
      if (context.mounted) {
        AppToast.showText(context, '✅ Logs copiados al portapapeles');
      }
    });
  }

  Future<void> _runNativeAuditor() async {
    DebugLogger.log('Iniciando auditoría nativa vía MethodChannel...');
    try {
      const channel = MethodChannel('com.heyzell.orpheus/app_control');
      final Map<dynamic, dynamic>? report =
          await channel.invokeMethod<Map<dynamic, dynamic>>('getNotificationDiagnostics');
      if (report != null) {
        DebugLogger.log('--- REPORTE NATIVO ANDROID ---');
        report.forEach((key, value) {
          DebugLogger.log('NATIVO [$key]: $value');
        });
        DebugLogger.log('------------------------------');
      } else {
        DebugLogger.log('REPORTE NATIVO: El canal no retornó datos.');
      }
    } catch (e, s) {
      DebugLogger.log('ERROR Auditoría Nativa: $e\n$s');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Telemetría de Audio',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              'In-App Audio & Foreground Service Logger',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: AppTheme.accent),
            tooltip: 'Ejecutar Auditoría Nativa (Java)',
            onPressed: _runNativeAuditor,
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_rounded, color: Colors.white),
            tooltip: 'Copiar todo al portapapeles',
            onPressed: () => _copyToClipboard(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            tooltip: 'Limpiar logs',
            onPressed: () {
              DebugLogger.clear();
              AppToast.showText(context, 'Logs borrados');
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: DebugLogger.logsNotifier,
        builder: (context, logs, _) {
          if (logs.isEmpty) {
            return const Center(
              child: Text(
                'No hay eventos registrados aún.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            );
          }

          if (_autoScroll && _scrollController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            });
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF1A1A1A),
                child: Row(
                  children: [
                    Text(
                      'Total eventos: ${logs.length}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const Text('Auto-scroll',
                            style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Switch(
                          value: _autoScroll,
                          activeThumbColor: AppTheme.accent,
                          onChanged: (val) {
                            setState(() {
                              _autoScroll = val;
                            });
                          },
                        ),
                      ],
                    )
                  ],
                ),
              ),
              Expanded(
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final logLine = logs[index];
                      Color textColor = Colors.white70;
                      if (logLine.contains('ERROR') || logLine.contains('Exception')) {
                        textColor = Colors.redAccent;
                      } else if (logLine.contains('playing=true') || logLine.contains('playing: true')) {
                        textColor = const Color(0xFF4CAF50);
                      } else if (logLine.contains('mediaItem.add')) {
                        textColor = const Color(0xFF64B5F6);
                      } else if (logLine.contains('NATIVO')) {
                        textColor = const Color(0xFFFFB74D);
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Text(
                          logLine,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: textColor,
                            height: 1.3,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _copyToClipboard(context),
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.copy_rounded, color: Colors.black),
        label: const Text('Copiar Logs', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
