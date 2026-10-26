import 'package:copilot_control_center/main.dart';
import 'package:copilot_control_center/src/features/workspace/demo_attachments.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class _PickedFile extends PlatformFile {
  _PickedFile(this.name, {this.size = 3});

  @override
  final String name;
  final int size;
  @override
  Uri get uri => Uri.parse('file:///$name');
  @override
  Never get xFile => throw UnsupportedError('Not used in this test');
  @override
  int lengthSync() => size;
  @override
  Future<int> length() async => size;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List(size);
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(Uint8List(size));
}

class _Picker extends FilePickerPlatform {
  List<PlatformFile> selection = [];
  bool fail = false;

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
  }) async {
    if (fail) throw PlatformException(code: 'PICK_FAILED');
    return selection;
  }
}

void main() {
  late _Picker picker;
  setUp(() {
    final previous = FilePickerPlatform.instance;
    picker = _Picker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ControlCenterApp());
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> select(WidgetTester tester, String label, String value) async {
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == label,
    );
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets('revision files are attached only after confirmation', (
    tester,
  ) async {
    await open(tester);
    picker.selection = [_PickedFile('review.pdf'), _PickedFile('example.png')];
    await tap(tester, 'Do poprawek');
    await tap(tester, 'Dodaj pliki');
    expect(find.text('review.pdf (1 KB)'), findsOneWidget);
    await tap(tester, 'Anuluj');
    expect(find.text('review.pdf (1 KB)'), findsNothing);
    await tap(tester, 'Do poprawek');
    await tap(tester, 'Dodaj pliki');
    await tester.enterText(
      input('Co zespół musi poprawić?'),
      'Porównaj z obrazem.',
    );
    await tap(tester, 'Przekaż do poprawek');
    expect(find.text('review.pdf (1 KB)'), findsOneWidget);
    expect(find.text('example.png (1 KB)'), findsOneWidget);
    expect(find.text('Porównaj z obrazem.'), findsOneWidget);
  });

  testWidgets('chat supports attachment-only messages and clears sent files', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'Asystent Budowlańca');
    await tap(tester, 'Tech Lead');
    picker.selection = [_PickedFile('brief.pdf')];
    await tap(tester, 'Dodaj pliki');
    await tap(tester, 'Wyślij');
    expect(find.text('brief.pdf (1 KB)'), findsOneWidget);
    expect(
      tester.widget<DemoAttachments>(find.byType(DemoAttachments)).files,
      isEmpty,
    );
    expect(find.text('Ty'), findsOneWidget);
  });

  testWidgets(
    'wizard keeps brief, files, accounts and assigned tasks on edit',
    (tester) async {
      await open(tester);
      await tap(tester, 'Zespoły AI');
      await tap(tester, 'Utwórz zespół');
      await tester.enterText(input('Nazwa zespołu'), 'Nowy portal');
      await select(tester, 'Główne konto GitHub (demo)', 'github-web');
      await select(
        tester,
        'Wspólne repozytorium (demo)',
        'github-web/copilot-control-center',
      );
      await tap(tester, 'GitHub');
      await select(tester, 'Tech Lead — konto GitHub (demo)', 'github-backend');
      await tap(tester, 'PDF');
      expect(find.text('Analizuj dokument przez AI'), findsNothing);
      await tester.enterText(
        input('Pełny opis zadania dla zespołu'),
        'Zbuduj portal z logowaniem.',
      );
      picker.selection = [_PickedFile('spec.pdf'), _PickedFile('mockup.jpg')];
      await tap(tester, 'Dodaj pliki');
      await tap(tester, 'Zadanie');
      await tap(tester, 'Analizuj dokument przez AI');
      expect(find.text('Analiza AI nie jest skonfigurowana'), findsOneWidget);
      await tap(tester, 'Rozumiem');
      expect(find.text('Opis taska'), findsNothing);
      await tap(tester, 'Dodaj task');
      await tester.enterText(
        input('Opis taska'),
        'Zaimplementuj formularz logowania',
      );
      await select(tester, 'Bot odpowiedzialny', 'Web Developer');
      await tap(tester, 'Zapis');
      await tap(tester, 'Zapisz zespół');
      await tap(tester, 'Edytuj zespół');
      await tap(tester, 'PDF');
      expect(find.text('spec.pdf (1 KB)'), findsOneWidget);
      expect(find.text('mockup.jpg (1 KB)'), findsOneWidget);
      expect(find.text('Zbuduj portal z logowaniem.'), findsOneWidget);
      await tap(tester, 'GitHub');
      expect(find.text('github-backend'), findsNWidgets(2));
      await tap(tester, 'Zadanie');
      await tap(tester, 'Web Developer (1)');
      expect(find.text('Zaimplementuj formularz logowania'), findsOneWidget);
      expect(find.text('Web Developer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'file validation, cancellation and removal preserve existing data',
    (tester) async {
      var files = <DemoFile>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => DemoAttachments(
                files: files,
                onChanged: (value) => update(() => files = value),
              ),
            ),
          ),
        ),
      );
      picker.selection = [_PickedFile('one.pdf')];
      await tap(tester, 'Dodaj pliki');
      expect(files.single.bytes, hasLength(3));
      picker.selection = [];
      await tap(tester, 'Dodaj pliki');
      expect(files, hasLength(1));
      picker.selection = [_PickedFile('large.zip', size: 10 * 1024 * 1024 + 1)];
      await tap(tester, 'Dodaj pliki');
      expect(
        find.text('Limit: 10 MB na plik i 30 MB łącznie.'),
        findsOneWidget,
      );
      expect(files, hasLength(1));
      picker.fail = true;
      await tap(tester, 'Dodaj pliki');
      expect(
        find.textContaining('Nie udało się wybrać lub odczytać plików:'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(files, isEmpty);
      picker.fail = false;
      picker.selection = [
        for (var i = 0; i < 3; i++)
          _PickedFile('limit-$i.pdf', size: 10 * 1024 * 1024),
      ];
      await tap(tester, 'Dodaj pliki');
      expect(files, hasLength(3));
      expect(
        files.fold<int>(0, (sum, file) => sum + file.size),
        30 * 1024 * 1024,
      );
      picker.selection = [_PickedFile('extra.txt', size: 1)];
      await tap(tester, 'Dodaj pliki');
      expect(
        find.text('Limit: 10 MB na plik i 30 MB łącznie.'),
        findsOneWidget,
      );
      expect(files, hasLength(3));
    },
  );
}
