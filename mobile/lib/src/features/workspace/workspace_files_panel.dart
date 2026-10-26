import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import 'demo_attachments.dart';
import 'workspace_data.dart';
import 'workspace_shell.dart';

class WorkspaceFilesPanel extends StatefulWidget {
  const WorkspaceFilesPanel({
    required this.api,
    required this.collection,
    required this.ownerId,
    required this.files,
    required this.onChanged,
    this.onPendingFilesChanged,
    super.key,
  });

  final ApiClient api;
  final String collection;
  final String ownerId;
  final List<WorkspaceFile> files;
  final VoidCallback onChanged;
  final ValueChanged<bool>? onPendingFilesChanged;

  @override
  State<WorkspaceFilesPanel> createState() => _WorkspaceFilesPanelState();
}

class _WorkspaceFilesPanelState extends State<WorkspaceFilesPanel> {
  List<DemoFile> _draft = [];
  bool _busy = false;
  String? _error;

  void _setDraft(List<DemoFile> files) {
    setState(() => _draft = files);
    widget.onPendingFilesChanged?.call(files.isNotEmpty);
  }

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final file in [..._draft]) {
        final response = await widget.api.uploadWorkspaceFile(
          collection: widget.collection,
          ownerId: widget.ownerId,
          filename: file.name,
          bytes: file.bytes,
        );
        parseWorkspaceFile(response['file']);
        if (!mounted) return;
        _setDraft([..._draft]..remove(file));
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Nie udało się przesłać wszystkich plików: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onChanged();
      }
    }
  }

  Future<void> _download(WorkspaceFile file) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await widget.api.downloadWorkspaceFile(file.id);
      if (!mounted) return;
      if (bytes.length != file.sizeBytes) {
        throw const ApiException(
          'INVALID_FILE_RESPONSE',
          'Pobrany plik ma inny rozmiar niż zapisane metadane.',
        );
      }
      await FilePicker.saveFile(
        fileName: file.filename,
        bytes: bytes,
        mimeType: 'application/octet-stream',
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Nie udało się pobrać pliku: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(WorkspaceFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć załącznik?'),
        content: Text(file.filename),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.deleteWorkspaceFile(file.id);
      if (mounted) widget.onChanged();
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Nie udało się usunąć pliku: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePanel(
    title: 'Załączniki',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.files.isEmpty)
          const Text('Brak plików zapisanych na serwerze.'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final file in widget.files)
              InputChip(
                avatar: const Icon(Icons.cloud_done, size: 16),
                label: Text(
                  '${file.filename} (${(file.sizeBytes / 1024).ceil()} KB)',
                ),
                tooltip: 'Pobierz plik',
                onPressed: _busy ? null : () => _download(file),
                onDeleted: _busy ? null : () => _delete(file),
              ),
          ],
        ),
        const SizedBox(height: 16),
        DemoAttachments(
          files: _draft,
          enabled: !_busy,
          existingBytes: widget.files.fold(
            0,
            (sum, file) => sum + file.sizeBytes,
          ),
          caption: 'PDF, obrazy i inne pliki · 10 MB/plik, 30 MB łącznie. Wybrane pliki wyślij przyciskiem poniżej.',
          onChanged: _setDraft,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy || _draft.isEmpty ? null : _upload,
          icon: const Icon(Icons.cloud_upload),
          label: const Text('Prześlij wybrane pliki'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
