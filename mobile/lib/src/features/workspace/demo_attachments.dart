import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class DemoFile {
  const DemoFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
  int get size => bytes.length;
}

class DemoAttachments extends StatefulWidget {
  const DemoAttachments({
    required this.files,
    required this.onChanged,
    this.existingBytes = 0,
    this.enabled = true,
    this.caption =
        'PDF, obrazy i inne pliki · 10 MB/plik, 30 MB łącznie · tylko lokalnie',
    super.key,
  });

  final List<DemoFile> files;
  final ValueChanged<List<DemoFile>> onChanged;
  final int existingBytes;
  final bool enabled;
  final String caption;

  @override
  State<DemoAttachments> createState() => _DemoAttachmentsState();
}

class _DemoAttachmentsState extends State<DemoAttachments> {
  bool _picking = false;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.pickFiles();
      if (!mounted || result.isEmpty) return;
      final files = [...widget.files];
      var total = files.fold<int>(
        widget.existingBytes,
        (sum, file) => sum + file.size,
      );
      for (final file in result) {
        final size = await file.length();
        if (!mounted) return;
        if (size == null) {
          setState(() => _error = 'Nie udało się odczytać rozmiaru pliku.');
          return;
        }
        if (size > 10 * 1024 * 1024 || total + size > 30 * 1024 * 1024) {
          setState(() => _error = 'Limit: 10 MB na plik i 30 MB łącznie.');
          return;
        }
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        if (bytes.length > 10 * 1024 * 1024 ||
            total + bytes.length > 30 * 1024 * 1024) {
          setState(() => _error = 'Limit: 10 MB na plik i 30 MB łącznie.');
          return;
        }
        if (bytes.isEmpty) {
          setState(() => _error = 'Wybierz niepusty plik.');
          return;
        }
        files.add(DemoFile(name: file.name, bytes: bytes));
        total += bytes.length;
      }
      widget.onChanged(files);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(
        () => _error = 'Nie udało się wybrać lub odczytać plików: $error',
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: !widget.enabled || _picking ? null : _pick,
        icon: const Icon(Icons.attach_file),
        label: Text(_picking ? 'Odczytywanie plików…' : 'Dodaj pliki'),
      ),
      Text(widget.caption),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      AttachmentList(
        files: widget.files,
        onRemove: !widget.enabled
            ? null
            : (index) => widget.onChanged([...widget.files]..removeAt(index)),
      ),
    ],
  );
}

class AttachmentList extends StatelessWidget {
  const AttachmentList({required this.files, this.onRemove, super.key});

  final List<DemoFile> files;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (var i = 0; i < files.length; i++)
        InputChip(
          avatar: const Icon(Icons.insert_drive_file, size: 16),
          label: Text('${files[i].name} (${(files[i].size / 1024).ceil()} KB)'),
          onDeleted: onRemove == null ? null : () => onRemove!(i),
        ),
    ],
  );
}
