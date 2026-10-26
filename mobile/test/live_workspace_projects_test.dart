import 'dart:async';
import 'dart:typed_data';

import 'package:copilot_control_center/src/control_center_theme.dart';
import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/features/auth/backend_workspace_app.dart';
import 'package:copilot_control_center/src/features/workspace/demo_attachments.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_data.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_repository_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/file_picker_fake.dart';

const _accounts = <WorkspaceAccount>[
  (id: 'main', login: 'owner', active: true, scopes: ['repo']),
  (id: 'other', login: 'secondary', active: true, scopes: ['repo']),
  (id: 'revoked', login: 'expired', active: false, scopes: ['repo']),
];

Map<String, dynamic> _repository(String name, {bool writable = true}) => {
  'id': name,
  'fullName': name,
  'canPush': writable,
};

Map<String, dynamic> _project() => {
  'id': 'project',
  'name': 'Real project',
  'description': 'Shared implementation',
  'repository': 'owner/repository',
  'mainGithubAccountId': 'main',
  'brief': 'Build accessible navigation.',
  'repositoryContext': 'Flutter web client.',
  'files': <Map<String, dynamic>>[],
  'documents': <Object>[],
  'tasks': [
    {
      'id': 'legacy-task',
      'title': 'Existing project-only task',
      'description': 'Preserve tasks outside teams.',
      'teamId': null,
      'botId': null,
      'priority': 'HIGH',
      'status': 'TODO',
    },
  ],
};

class _ProjectApi extends ApiClient {
  final projects = <Map<String, dynamic>>[];
  final requests = <String>[];
  final writes = <({String path, String method, Map<String, dynamic> body})>[];
  final repositoryResponses = <String, Future<Map<String, dynamic>>>{};
  final uploaded =
      <({String collection, String owner, String filename, Uint8List bytes})>[];
  final content = <String, Uint8List>{};
  ApiException? saveError;
  String? uploadFailure;
  Completer<Uint8List>? downloadPending;
  bool deleteConfirmed = true;
  int _fileSequence = 0;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    requests.add('$method $path');
    if (path == '/session') {
      return {
        'user': {'id': 'owner'},
        'githubAccounts': [
          for (final account in _accounts)
            {
              'id': account.id,
              'login': account.login,
              'status': account.active ? 'ACTIVE' : 'REVOKED',
              'scopes': account.scopes,
            },
        ],
      };
    }
    if (path == '/workspace') {
      return {'definitions': [], 'projects': projects, 'teams': []};
    }
    if (path.startsWith('/github/accounts/')) {
      return repositoryResponses[path] ??
          Future.value({
            'repositories': [_repository('owner/repository')],
            'nextPage': null,
          });
    }
    final body = data == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(data as Map);
    writes.add((path: path, method: method, body: body));
    if (saveError != null) throw saveError!;
    if (path == '/workspace/projects' && method == 'POST') {
      final project = {
        ..._project(),
        ...body,
        'id': 'created-project',
        'mainGithubAccountId': body['githubAccountId'],
        'tasks': <Object>[],
      };
      projects.add(project);
      return {'project': project};
    }
    if (path.startsWith('/workspace/projects/') && method == 'PATCH') {
      projects
          .firstWhere((project) => path.endsWith('/${project['id']}'))
          .addAll(body);
      return {'ok': true};
    }
    if (path.startsWith('/workspace/files/') && method == 'DELETE') {
      if (deleteConfirmed) {
        final id = Uri.decodeComponent(path.split('/').last);
        for (final project in projects) {
          (project['files'] as List).removeWhere(
            (file) => (file as Map)['id'] == id,
          );
        }
        content.remove(id);
      }
      return {'ok': deleteConfirmed};
    }
    throw StateError('Unexpected request: $method $path');
  }

  @override
  Future<Map<String, dynamic>> uploadWorkspaceFile({
    required String collection,
    required String ownerId,
    required String filename,
    required Uint8List bytes,
  }) async {
    uploaded.add((
      collection: collection,
      owner: ownerId,
      filename: filename,
      bytes: Uint8List.fromList(bytes),
    ));
    if (filename == uploadFailure) {
      throw const ApiException('UPLOAD_FAILED', 'Upload interrupted.');
    }
    final file = {
      'id': 'file-${++_fileSequence}',
      'filename': filename,
      'sizeBytes': bytes.length,
    };
    (projects.single['files'] as List).add(file);
    content[file['id']! as String] = Uint8List.fromList(bytes);
    return {'file': file};
  }

  @override
  Future<Uint8List> downloadWorkspaceFile(String fileId) async =>
      downloadPending?.future ?? Uint8List.fromList(content[fileId]!);

  @override
  Future<void> deleteWorkspaceFile(String fileId) async {
    final response = await request(
      '/workspace/files/${Uri.encodeComponent(fileId)}',
      method: 'DELETE',
    );
    if (response['ok'] != true) {
      throw const ApiException(
        'INVALID_FILE_RESPONSE',
        'Serwer nie potwierdził usunięcia pliku.',
      );
    }
  }
}

Future<void> _mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1440, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

Future<void> _projects(
  WidgetTester tester,
  _ProjectApi api, {
  bool details = false,
}) async {
  await _mount(
    tester,
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: BackendWorkspaceApp(
        initialUri: Uri.parse('https://example.test/workspace'),
      ),
    ),
  );
  await _tap(tester, 'Projekty i PDF');
  if (details) await _tap(tester, 'Real project');
}

Future<void> _tap(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String label, String value) async {
  final field = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == label,
  );
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
}

void main() {
  late TestFilePicker picker;
  setUp(() {
    final previous = FilePickerPlatform.instance;
    picker = TestFilePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
  });

  testWidgets('repository selector ignores stale account replies', (
    tester,
  ) async {
    final api = _ProjectApi();
    final first = Completer<Map<String, dynamic>>();
    api.repositoryResponses['/github/accounts/main/repositories?page=1'] =
        first.future;
    api.repositoryResponses['/github/accounts/other/repositories?page=1'] =
        Future.value({
          'repositories': [_repository('secondary/current')],
          'nextPage': null,
        });
    final selections = <WorkspaceRepositorySelection?>[];
    await _mount(
      tester,
      MaterialApp(
        theme: controlCenterTheme(),
        home: Scaffold(
          body: WorkspaceRepositoryPicker(
            api: api,
            accounts: _accounts,
            onChanged: selections.add,
          ),
        ),
      ),
    );
    final accountField = find.byType(DropdownButtonFormField<String>).first;
    await tester.tap(accountField);
    await tester.pumpAndSettle();
    expect(find.text('@expired'), findsNothing);
    await tester.tap(find.text('@owner').last);
    await tester.pump();
    await tester.tap(accountField);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('@secondary').last);
    await tester.pumpAndSettle();
    first.complete({
      'repositories': [_repository('owner/outdated')],
      'nextPage': null,
    });
    await tester.pumpAndSettle();
    await _select(tester, 'Wspólne repozytorium', 'secondary/current');
    expect(selections.last, (
      accountId: 'other',
      repository: 'secondary/current',
    ));
    expect(find.text('owner/outdated'), findsNothing);
  });

  testWidgets(
    'projects use paginated repositories and persist selected account',
    (tester) async {
      final api = _ProjectApi();
      api.repositoryResponses['/github/accounts/main/repositories?page=1'] =
          Future.value({
            'repositories': [_repository('owner/read-only', writable: false)],
            'nextPage': 2,
          });
      api.repositoryResponses['/github/accounts/main/repositories?page=2'] =
          Future.value({
            'repositories': [_repository('owner/repository')],
            'nextPage': null,
          });
      await _projects(tester, api);
      await _tap(tester, 'Dodaj projekt');
      await _fill(tester, 'Nazwa projektu', 'New shared project');
      await _fill(tester, 'Pełny opis zadania dla botów', 'Build navigation.');
      await _select(tester, 'Główne konto GitHub projektu', '@owner');
      final repositoryField = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is DropdownButtonFormField<String> &&
                widget.decoration.labelText == 'Wspólne repozytorium',
          ),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(repositoryField.items!.single.enabled, isFalse);
      await _tap(tester, 'Wczytaj więcej repozytoriów');
      await _select(tester, 'Wspólne repozytorium', 'owner/repository');
      await _tap(tester, 'Zapisz projekt');
      expect(api.writes.single.body, {
        'name': 'New shared project',
        'description': '',
        'brief': 'Build navigation.',
        'githubAccountId': 'main',
        'repository': 'owner/repository',
      });
      expect(find.text('Szczegóły zadania'), findsOneWidget);
      expect(find.text('New shared project'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _projects(tester, api);
      expect(find.text('New shared project'), findsOneWidget);
    },
  );

  testWidgets(
    'project save error retains form and cancellation never creates data',
    (tester) async {
      final api = _ProjectApi()
        ..saveError = const ApiException(
          'REPOSITORY_ACCESS_DENIED',
          'Write access denied.',
        );
      await _projects(tester, api);
      await _tap(tester, 'Dodaj projekt');
      await _fill(tester, 'Nazwa projektu', 'Unpublished project');
      await _select(tester, 'Główne konto GitHub projektu', '@owner');
      await _select(tester, 'Wspólne repozytorium', 'owner/repository');
      await _tap(tester, 'Zapisz projekt');
      expect(find.text('Write access denied.'), findsOneWidget);
      expect(api.projects, isEmpty);
      expect(find.text('Unpublished project'), findsOneWidget);
      await _tap(tester, 'Anuluj');
      expect(find.text('Szczegóły zadania'), findsNothing);
      expect(api.projects, isEmpty);
    },
  );

  testWidgets(
    'project detail preserves project-only tasks and edits shared context',
    (tester) async {
      final api = _ProjectApi()..projects.add(_project());
      await _projects(tester, api, details: true);
      expect(find.text('Existing project-only task'), findsOneWidget);
      expect(find.text('Utwórz zespół'), findsNothing);
      expect(find.text('Analizuj dokument przez AI'), findsNothing);
      await _tap(tester, 'Edytuj opis i materiały');
      await _fill(
        tester,
        'Kontekst repozytorium dla botów',
        'Shared architecture notes.',
      );
      await _tap(tester, 'Zapisz projekt');
      expect(api.writes.single.method, 'PATCH');
      expect(api.writes.single.body, {
        'name': 'Real project',
        'description': 'Shared implementation',
        'brief': 'Build accessible navigation.',
        'repositoryContext': 'Shared architecture notes.',
      });
      expect(find.text('Shared architecture notes.'), findsOneWidget);
      expect(find.text('Existing project-only task'), findsOneWidget);
    },
  );

  testWidgets(
    'binary files upload and download without converting remote metadata to empty files',
    (tester) async {
      final api = _ProjectApi()..projects.add(_project());
      final bytes = Uint8List.fromList([0, 255, 17, 128]);
      picker.selection = [
        TestPickedFile('brief.pdf', data: bytes),
        TestPickedFile('image.png', data: bytes),
        TestPickedFile('archive.zip', data: bytes),
      ];
      await _projects(tester, api, details: true);
      await _tap(tester, 'Dodaj pliki');
      expect(api.uploaded, isEmpty);
      await _tap(tester, 'Prześlij wybrane pliki');
      expect(api.uploaded.map((file) => file.filename), [
        'brief.pdf',
        'image.png',
        'archive.zip',
      ]);
      for (final file in api.uploaded) {
        expect(file.collection, 'projects');
        expect(file.owner, 'project');
        expect(file.bytes, orderedEquals(bytes));
      }
      expect(
        tester.widget<DemoAttachments>(find.byType(DemoAttachments)).files,
        isEmpty,
      );
      await _tap(tester, 'archive.zip (1 KB)');
      expect(picker.saved.single.filename, 'archive.zip');
      expect(picker.saved.single.bytes, orderedEquals(bytes));
      await tester.pumpWidget(const SizedBox());
      await _projects(tester, api, details: true);
      expect(find.text('brief.pdf (1 KB)'), findsOneWidget);
      expect(
        tester.widget<DemoAttachments>(find.byType(DemoAttachments)).files,
        isEmpty,
      );
    },
  );

  testWidgets('partial upload keeps only unsent drafts for explicit retry', (
    tester,
  ) async {
    final api = _ProjectApi()
      ..projects.add(_project())
      ..uploadFailure = 'second.png';
    picker.selection = [
      TestPickedFile('first.pdf'),
      TestPickedFile('second.png'),
    ];
    await _projects(tester, api, details: true);
    await _tap(tester, 'Dodaj pliki');
    await _tap(tester, 'Prześlij wybrane pliki');
    expect(find.textContaining('Upload interrupted.'), findsOneWidget);
    expect(find.text('first.pdf (1 KB)'), findsOneWidget);
    expect(
      tester
          .widget<DemoAttachments>(find.byType(DemoAttachments))
          .files
          .single
          .name,
      'second.png',
    );
    api.uploadFailure = null;
    await _tap(tester, 'Prześlij wybrane pliki');
    expect(api.uploaded.map((file) => file.filename), [
      'first.pdf',
      'second.png',
      'second.png',
    ]);
    expect(find.text('second.png (1 KB)'), findsOneWidget);
    expect(
      tester.widget<DemoAttachments>(find.byType(DemoAttachments)).files,
      isEmpty,
    );
  });

  testWidgets(
    'file quota includes existing server files and accepts exactly 30 MB',
    (tester) async {
      final project = _project();
      project['files'] = [
        {'id': 'first', 'filename': 'first.pdf', 'sizeBytes': 10 * 1024 * 1024},
        {
          'id': 'second',
          'filename': 'second.pdf',
          'sizeBytes': 10 * 1024 * 1024,
        },
      ];
      final api = _ProjectApi()..projects.add(project);
      await _projects(tester, api, details: true);
      picker.selection = [TestPickedFile('exact.pdf', size: 10 * 1024 * 1024)];
      await _tap(tester, 'Dodaj pliki');
      expect(
        tester
            .widget<DemoAttachments>(find.byType(DemoAttachments))
            .files
            .single
            .size,
        10 * 1024 * 1024,
      );
      picker.selection = [TestPickedFile('extra.txt', size: 1)];
      await _tap(tester, 'Dodaj pliki');
      expect(
        find.text('Limit: 10 MB na plik i 30 MB łącznie.'),
        findsOneWidget,
      );
      expect(
        tester.widget<DemoAttachments>(find.byType(DemoAttachments)).files,
        hasLength(1),
      );
      expect(api.uploaded, isEmpty);
    },
  );

  testWidgets('empty files are rejected before upload', (tester) async {
    final api = _ProjectApi()..projects.add(_project());
    picker.selection = [TestPickedFile('empty.txt', size: 0)];
    await _projects(tester, api, details: true);
    await _tap(tester, 'Dodaj pliki');
    expect(find.text('Wybierz niepusty plik.'), findsOneWidget);
    expect(api.uploaded, isEmpty);
    expect(
      tester.widget<DemoAttachments>(find.byType(DemoAttachments)).files,
      isEmpty,
    );
  });

  testWidgets(
    'file deletion requires confirmation and actual server acknowledgement',
    (tester) async {
      final project = _project();
      project['files'] = [
        {'id': 'stored', 'filename': 'stored.bin', 'sizeBytes': 3},
      ];
      final api = _ProjectApi()
        ..projects.add(project)
        ..deleteConfirmed = false;
      await _projects(tester, api, details: true);
      Future<void> remove() async {
        final chip = tester.widget<InputChip>(
          find.widgetWithText(InputChip, 'stored.bin (1 KB)'),
        );
        chip.onDeleted!();
        await tester.pumpAndSettle();
      }

      await remove();
      await _tap(tester, 'Anuluj');
      expect(api.writes, isEmpty);
      await remove();
      await _tap(tester, 'Usuń');
      expect(
        find.textContaining('Serwer nie potwierdził usunięcia'),
        findsOneWidget,
      );
      expect(find.text('stored.bin (1 KB)'), findsOneWidget);
      api.deleteConfirmed = true;
      await remove();
      await _tap(tester, 'Usuń');
      expect(find.text('stored.bin (1 KB)'), findsNothing);
    },
  );

  testWidgets(
    'download finishing after navigation does not open a save dialog',
    (tester) async {
      final project = _project();
      project['files'] = [
        {'id': 'stored', 'filename': 'stored.bin', 'sizeBytes': 3},
      ];
      final api = _ProjectApi()
        ..projects.add(project)
        ..downloadPending = Completer<Uint8List>();
      await _projects(tester, api, details: true);
      final chip = find.text('stored.bin (1 KB)');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      api.downloadPending!.complete(Uint8List(3));
      await tester.pumpAndSettle();
      expect(picker.saved, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
