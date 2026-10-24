import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/services/sync_download_manager.dart';
import '../theme/app_theme.dart';

/// Interactive UI panel providing real-time visibility into offline download
/// progress, active download speed, checksum verification, and queue controls.
class SyncProgressPanel extends StatefulWidget {
  const SyncProgressPanel({
    super.key,
    this.manager,
    this.isEmbedded = false,
  });

  final SyncDownloadManager? manager;
  final bool isEmbedded;

  /// Convenience helper to present [SyncProgressPanel] as a modal bottom sheet.
  static Future<void> showModal(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const SyncProgressPanel(),
    );
  }

  @override
  State<SyncProgressPanel> createState() => _SyncProgressPanelState();
}

class _SyncProgressPanelState extends State<SyncProgressPanel> {
  late final SyncDownloadManager _manager;
  StreamSubscription<SyncDownloadTask>? _taskSub;

  @override
  void initState() {
    super.initState();
    _manager = widget.manager ?? SyncDownloadManager.instance;
    _taskSub = _manager.onTaskUpdated.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _taskSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panelContent = ValueListenableBuilder<SyncProgressSummary>(
      valueListenable: _manager.summaryNotifier,
      builder: (context, summary, _) {
        final tasks = _manager.allTasks;

        return Column(
          mainAxisSize: widget.isEmbedded ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle if modal
            if (!widget.isEmbedded)
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
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.cloud_sync_rounded,
                      color: AppTheme.accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sincronización Offline',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary.isIdle
                              ? (tasks.isEmpty
                                  ? 'Sin descargas activas'
                                  : '${summary.completedTasks} completadas')
                              : '${summary.activeTasks} activa(s) • ${summary.queuedTasks} en cola',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!summary.isIdle)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            size: 13,
                            color: Colors.cyanAccent,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _formatOverallSpeed(summary.overallSpeedBytesPerSec),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.cyanAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Global Progress Bar
            if (!summary.isIdle || summary.totalTasks > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: summary.overallProgress,
                        backgroundColor: AppTheme.bgHover,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.accent,
                        ),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(summary.overallProgress * 100).round()}% completado',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppTheme.textHint,
                          ),
                        ),
                        Text(
                          '${summary.completedTasks}/${summary.totalTasks} pistas',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            color: AppTheme.textHint,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Controls row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  if (!summary.isIdle)
                    TextButton.icon(
                      onPressed: () => _manager.cancelAll(),
                      icon: const Icon(
                        Icons.stop_circle_outlined,
                        size: 16,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        'Cancelar todo',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: Colors.redAccent,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  const Spacer(),
                  if (tasks.any((t) => t.isFinished))
                    TextButton.icon(
                      onPressed: () => _manager.clearFinishedTasks(),
                      icon: const Icon(
                        Icons.clear_all_rounded,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                      label: const Text(
                        'Limpiar terminadas',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                ],
              ),
            ),

            const Divider(color: AppTheme.divider, height: 1),

            // Task list
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.download_done_rounded,
                        size: 38,
                        color: AppTheme.textHint.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'No hay descargas en curso',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Conecta un nodo en red local para sincronizar álbumes y pistas.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          color: AppTheme.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (widget.isEmbedded)
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppTheme.divider, height: 1),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _TaskTile(
                      task: task,
                      onCancel: () => _manager.cancel(task.trackId),
                    );
                  },
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: AppTheme.divider, height: 1),
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _TaskTile(
                      task: task,
                      onCancel: () => _manager.cancel(task.trackId),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );

    if (widget.isEmbedded) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: panelContent,
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(child: panelContent),
    );
  }

  String _formatOverallSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onCancel,
  });

  final SyncDownloadTask task;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Status icon
          _buildStatusIcon(),
          const SizedBox(width: 12),
          // Title + Artist + Progress info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.track.displayArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _buildSubtitleStatus(),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: task.status == SyncDownloadStatus.failed
                            ? Colors.redAccent
                            : AppTheme.textHint,
                      ),
                    ),
                  ],
                ),
                if (task.status == SyncDownloadStatus.downloading) ...[
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      backgroundColor: AppTheme.bgHover,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.cyanAccent,
                      ),
                      minHeight: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Cancel / Action Button
          if (!task.isFinished)
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppTheme.textHint,
              ),
              onPressed: onCancel,
              tooltip: 'Cancelar descarga',
            )
          else if (task.status == SyncDownloadStatus.completed)
            const Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: Colors.greenAccent,
            )
          else if (task.status == SyncDownloadStatus.failed)
            const Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: Colors.redAccent,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (task.status) {
      case SyncDownloadStatus.queued:
        return const Icon(
          Icons.schedule_rounded,
          size: 20,
          color: AppTheme.textHint,
        );
      case SyncDownloadStatus.downloading:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
          ),
        );
      case SyncDownloadStatus.verifying:
        return const Icon(
          Icons.verified_user_rounded,
          size: 18,
          color: Colors.cyanAccent,
        );
      case SyncDownloadStatus.completed:
        return const Icon(
          Icons.download_done_rounded,
          size: 20,
          color: Colors.greenAccent,
        );
      case SyncDownloadStatus.failed:
        return const Icon(
          Icons.warning_amber_rounded,
          size: 20,
          color: Colors.redAccent,
        );
      case SyncDownloadStatus.cancelled:
        return const Icon(
          Icons.block_rounded,
          size: 18,
          color: AppTheme.textHint,
        );
    }
  }

  String _buildSubtitleStatus() {
    switch (task.status) {
      case SyncDownloadStatus.queued:
        return '• En cola';
      case SyncDownloadStatus.downloading:
        return '• ${task.percentage}% (${task.formattedSpeed})';
      case SyncDownloadStatus.verifying:
        return '• Verificando SHA-256...';
      case SyncDownloadStatus.completed:
        return '• Completado';
      case SyncDownloadStatus.failed:
        return '• Error';
      case SyncDownloadStatus.cancelled:
        return '• Cancelado';
    }
  }
}
