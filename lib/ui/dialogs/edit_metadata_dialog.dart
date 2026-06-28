import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/models/track.dart';
import '../../core/services/album_art_fetcher_service.dart';
import '../../core/services/lyrics_service.dart';
import '../theme/app_theme.dart';

/// Premium metadata editor dialog — Tidal-inspired dark aesthetic.
///
/// Opens as a modal dialog from the track context menu. Allows the user
/// to edit [Track.customMetadata] fields (title, artist, album) without
/// touching the physical file. Optionally re-identifies cover art and
/// lyrics with the corrected strings via the built-in services.
///
/// Usage:
/// ```dart
/// final changed = await showDialog<bool>(
///   context: context,
///   builder: (_) => EditMetadataDialog(track: track),
/// );
/// if (changed == true) _refreshData();
/// ```
class EditMetadataDialog extends StatefulWidget {
  const EditMetadataDialog({super.key, required this.track});

  final Track track;

  @override
  State<EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends State<EditMetadataDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _artistCtrl;
  late final TextEditingController _albumCtrl;

  bool _reidentify = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.track.displayTitle);
    _artistCtrl = TextEditingController(text: widget.track.displayArtist);
    _albumCtrl = TextEditingController(text: widget.track.displayAlbum);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns true if the user has changed any of the text fields.
  bool get _hasChanges =>
      _titleCtrl.text.trim() != widget.track.displayTitle ||
      _artistCtrl.text.trim() != widget.track.displayArtist ||
      _albumCtrl.text.trim() != widget.track.displayAlbum;

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final track = widget.track;

    await LocalDatabase.instance.updateTrackMetadata(
      track,
      newTitle: _titleCtrl.text,
      newArtist: _artistCtrl.text,
      newAlbum: _albumCtrl.text,
      resetMediaFlags: _reidentify,
    );

    // Fire re-identification in the background — don't block the UI.
    if (_reidentify) {
      AlbumArtFetcherService.instance.processTrack(track);
      LyricsService.instance.fetchLyrics(track);
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final coverPath = track.customMetadata.customCoverPath;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Container(
        width: 520,
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(200),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            _buildHeader(coverPath, track),

            // ── Divider ───────────────────────────────────────────────────
            const Divider(height: 1, color: AppTheme.divider),

            // ── Form fields ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildField(
                    id: 'edit-title-field',
                    label: 'Título',
                    controller: _titleCtrl,
                    icon: Icons.music_note_rounded,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    id: 'edit-artist-field',
                    label: 'Artista',
                    controller: _artistCtrl,
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 16),
                  _buildField(
                    id: 'edit-album-field',
                    label: 'Álbum',
                    controller: _albumCtrl,
                    icon: Icons.album_rounded,
                  ),
                  const SizedBox(height: 24),

                  // ── Warning banner ─────────────────────────────────────
                  _buildWarningBanner(),
                  const SizedBox(height: 20),

                  // ── Re-identification switch ───────────────────────────
                  _buildReidentifySwitch(),
                  const SizedBox(height: 28),
                ],
              ),
            ),

            // ── Divider ───────────────────────────────────────────────────
            const Divider(height: 1, color: AppTheme.divider),

            // ── Action buttons ────────────────────────────────────────────
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String? coverPath, Track track) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: Row(
        children: [
          // Miniatura de portada
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: coverPath != null
                  ? Image.file(File(coverPath), fit: BoxFit.cover)
                  : Container(
                      color: AppTheme.bgHover,
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: AppTheme.textHint,
                        size: 28,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EDITAR INFORMACIÓN',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String id,
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return TextField(
      key: ValueKey(id),
      controller: controller,
      enabled: !_isSaving,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: AppTheme.textHint, size: 18),
        filled: true,
        fillColor: AppTheme.bgHover,
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.divider.withAlpha(80)),
        ),
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withAlpha(60),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.shade700.withAlpha(100)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.amber.shade600,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Nota: Cambiar el nombre o artista modificará el criterio de búsqueda local. '
              'Si los datos son incorrectos, el sistema podría no encontrar portadas o letras.',
              style: TextStyle(
                color: Colors.amber.shade400,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReidentifySwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _reidentify
            ? AppTheme.accent.withAlpha(20)
            : AppTheme.bgHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _reidentify ? AppTheme.accent.withAlpha(80) : AppTheme.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 16,
            color: _reidentify ? AppTheme.accent : AppTheme.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buscar portadas y letras con los nuevos datos',
                  style: TextStyle(
                    color: _reidentify ? AppTheme.textPrimary : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Conectará con iTunes y LRCLIB en segundo plano',
                  style: TextStyle(
                    color: _reidentify
                        ? AppTheme.textSecondary
                        : AppTheme.textHint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            key: const ValueKey('reidentify-switch'),
            value: _reidentify,
            onChanged: _isSaving ? null : (v) => setState(() => _reidentify = v),
            activeColor: AppTheme.accent,
            activeTrackColor: AppTheme.accent.withAlpha(80),
            inactiveThumbColor: AppTheme.textHint,
            inactiveTrackColor: AppTheme.divider,
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: const ValueKey('edit-cancel-btn'),
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancelar', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            height: 40,
            child: ElevatedButton(
              key: const ValueKey('edit-save-btn'),
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.bgDeep,
                      ),
                    )
                  : const Text(
                      'Guardar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
