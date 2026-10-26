import 'dart:convert';
import 'dart:typed_data';

import 'package:copilot_control_center/src/core/api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <Uint8List>[];
  ResponseBody Function(RequestOptions) response = (_) =>
      ResponseBody.fromString(
        '{"file":{"id":"file-id","filename":"fixture.bin"}}',
        201,
        headers: {
          'content-type': ['application/json'],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = BytesBuilder();
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.add(chunk);
      }
    }
    bodies.add(bytes.takeBytes());
    return response(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Adapter adapter;
  late ApiClient api;
  late Dio dio;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'control_center.session': 'fixture-session',
      'control_center.csrf': 'fixture-csrf',
    });
    adapter = _Adapter();
    dio = Dio(BaseOptions(baseUrl: 'https://workspace.example.test/api'))
      ..httpClientAdapter = adapter;
    api = ApiClient(dio: dio);
  });

  tearDown(() => dio.close(force: true));

  test(
    'uploads the original binary bytes with authentication and CSRF',
    () async {
      final bytes = Uint8List.fromList([0, 255, 13, 10, 37, 128, 129]);
      final result = await api.uploadWorkspaceFile(
        collection: 'messages',
        ownerId: 'message-id',
        filename: 'obraz i opis.bin',
        bytes: bytes,
      );
      expect(result['file']['id'], 'file-id');
      expect(adapter.bodies.single, orderedEquals(bytes));
      final request = adapter.requests.single;
      expect(request.path, '/workspace/messages/message-id/files');
      expect(request.contentType, 'application/octet-stream');
      expect(request.queryParameters['filename'], 'obraz i opis.bin');
      expect(request.headers['Authorization'], 'Bearer fixture-session');
      expect(request.headers['X-CSRF-Token'], 'fixture-csrf');
    },
  );

  test(
    'accepts exactly 10 MB and rejects one byte over the limit before upload',
    () async {
      await api.uploadWorkspaceFile(
        collection: 'projects',
        ownerId: 'project-id',
        filename: 'limit.bin',
        bytes: Uint8List(10 * 1024 * 1024),
      );
      expect(adapter.bodies.single.length, 10 * 1024 * 1024);
      await expectLater(
        api.uploadWorkspaceFile(
          collection: 'projects',
          ownerId: 'project-id',
          filename: 'oversized.bin',
          bytes: Uint8List(10 * 1024 * 1024 + 1),
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'FILE_TOO_LARGE',
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    },
  );

  test('empty files and unknown collections cannot be uploaded', () async {
    await expectLater(
      api.uploadWorkspaceFile(
        collection: 'revisions',
        ownerId: 'revision-id',
        filename: 'empty.bin',
        bytes: Uint8List(0),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'FILE_REQUIRED',
        ),
      ),
    );
    await expectLater(
      api.uploadWorkspaceFile(
        collection: 'other',
        ownerId: 'owner-id',
        filename: 'file.bin',
        bytes: Uint8List(1),
      ),
      throwsArgumentError,
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    'server upload failures propagate instead of reporting a saved file',
    () async {
      adapter.response = (_) => ResponseBody.fromString(
        jsonEncode({
          'error': {'code': 'ATTACHMENTS_TOO_LARGE'},
        }),
        413,
        headers: {
          'content-type': ['application/json'],
        },
      );
      await expectLater(
        api.uploadWorkspaceFile(
          collection: 'projects',
          ownerId: 'project-id',
          filename: 'file.bin',
          bytes: Uint8List(1),
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'ATTACHMENTS_TOO_LARGE',
          ),
        ),
      );
    },
  );

  test(
    'a response without file metadata is not an upload confirmation',
    () async {
      adapter.response = (_) => ResponseBody.fromString(
        '{}',
        201,
        headers: {
          'content-type': ['application/json'],
        },
      );
      await expectLater(
        api.uploadWorkspaceFile(
          collection: 'projects',
          ownerId: 'project-id',
          filename: 'file.bin',
          bytes: Uint8List(1),
        ),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'INVALID_FILE_RESPONSE',
          ),
        ),
      );
    },
  );

  test('downloads arbitrary binary files without text conversion', () async {
    final bytes = Uint8List.fromList([0, 255, 128, 13, 10]);
    adapter.response = (_) => ResponseBody(
      Stream.value(bytes),
      200,
      headers: {
        'content-type': ['application/octet-stream'],
      },
    );
    expect(await api.downloadWorkspaceFile('file-id'), orderedEquals(bytes));
    expect(adapter.requests.single.path, '/workspace/files/file-id/download');
  });

  test(
    'file deletion accepts the API 204 response with authentication and CSRF',
    () async {
      adapter.response = (_) => ResponseBody.fromString('', 204);
      await api.deleteWorkspaceFile('file-id');
      final request = adapter.requests.single;
      expect(request.method, 'DELETE');
      expect(request.path, '/workspace/files/file-id');
      expect(request.headers['Authorization'], isNotEmpty);
      expect(request.headers['X-CSRF-Token'], 'fixture-csrf');
    },
  );

  test(
    'unexpected deletion acknowledgements and server errors propagate',
    () async {
      adapter.response = (_) => ResponseBody.fromString(
        '{"ok":false}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
      await expectLater(
        api.deleteWorkspaceFile('file-id'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'INVALID_FILE_RESPONSE',
          ),
        ),
      );
      adapter.response = (_) => ResponseBody.fromString(
        '{"error":{"code":"FILE_NOT_FOUND"}}',
        404,
        headers: {
          'content-type': ['application/json'],
        },
      );
      await expectLater(
        api.deleteWorkspaceFile('file-id'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'FILE_NOT_FOUND',
          ),
        ),
      );
    },
  );

  test(
    'cookie-based sessions are checked even without a locally stored token',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      adapter.response = (_) => ResponseBody.fromString(
        '{"user":{"id":"cookie-user"},"githubAccounts":[]}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
      final session = await api.loadSession();
      expect(session['user']['id'], 'cookie-user');
      expect(adapter.requests.single.path, '/session');
      expect(adapter.requests.single.extra['withCredentials'], isTrue);
      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    },
  );
}
