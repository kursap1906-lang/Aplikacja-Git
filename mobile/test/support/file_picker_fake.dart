import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

final class TestPickedFile extends PlatformFile {
  TestPickedFile(this.name, {this.size = 3, this.data});

  @override
  final String name;
  final int size;
  final Uint8List? data;

  @override
  Uri get uri => Uri.file('/$name');
  @override
  Never get xFile => throw UnsupportedError('Not used in this test');
  @override
  int lengthSync() => data?.length ?? size;
  @override
  Future<int> length() async => lengthSync();
  @override
  Future<Uint8List> readAsBytes() async => data ?? Uint8List(size);
  @override
  Stream<Uint8List> readAsByteStream() => Stream.fromFuture(readAsBytes());
}

class TestFilePicker extends FilePickerPlatform {
  List<PlatformFile> selection = [];
  final saved = <({String filename, Uint8List bytes, String mimeType})>[];

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => selection;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    saved.add((
      filename: fileName,
      bytes: Uint8List.fromList(bytes),
      mimeType: mimeType,
    ));
    return Uri.file('/saved/$fileName');
  }
}
