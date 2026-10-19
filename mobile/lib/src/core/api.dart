import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _sessionKey = 'control_center.session';
const _csrfKey = 'control_center.csrf';
const _oauthStateKey = 'control_center.oauth_state';
const _configuredApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:3000/api',
);
final _apiBaseUrl = kIsWeb ? Uri.base.resolve('/api').toString() : _configuredApiBaseUrl;

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  ApiClient({FlutterSecureStorage? storage, Dio? dio})
      : _storage = storage ?? const FlutterSecureStorage(),
        _dio = dio ?? Dio(BaseOptions(
          baseUrl: _apiBaseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          headers: const {'Accept': 'application/json'},
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final session = await _storage.read(key: _sessionKey);
        if (session != null && session.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $session';
          final csrf = await _storage.read(key: _csrfKey);
          if (csrf != null && csrf.isNotEmpty) {
            options.headers['X-CSRF-Token'] = csrf;
          }
        }
        handler.next(options);
      },
    ));
  }

  final FlutterSecureStorage _storage;
  final Dio _dio;

  Future<void> registerAccount({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await request(
      '/auth/register',
      method: 'POST',
      data: {
        'email': email,
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
      },
    );
    await _storeSession(response);
  }

  Future<void> signIn({required String email, required String password}) async {
    final response = await request(
      '/auth/login',
      method: 'POST',
      data: {'email': email, 'password': password},
    );
    await _storeSession(response);
  }

  Future<void> _storeSession(Map<String, dynamic> response) async {
    final session = response['sessionToken'];
    final csrf = response['csrfToken'];
    if (session is! String || csrf is! String) {
      throw const ApiException('INVALID_SESSION_RESPONSE', 'Serwer nie zwrócił prawidłowej sesji.');
    }
    await _storage.write(key: _sessionKey, value: session);
    await _storage.write(key: _csrfKey, value: csrf);
  }

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    try {
      final response = await _dio.request<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(
          method: method,
          extra: withCredentials ? const {'withCredentials': true} : null,
        ),
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      final body = error.response?.data;
      if (body is Map && body['error'] is Map) {
        final apiError = Map<String, dynamic>.from(body['error'] as Map);
        throw ApiException(
          apiError['code'] as String? ?? 'API_ERROR',
          apiError['message'] as String? ?? 'Nie udało się wykonać operacji.',
          error.response?.statusCode,
        );
      }
      final unavailable = error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout;
      throw ApiException(
        unavailable ? 'SERVER_UNAVAILABLE' : 'NETWORK_ERROR',
        unavailable
            ? 'Nie można połączyć się z serwerem. Sprawdź API_BASE_URL i uruchom backend.'
            : 'Nie udało się połączyć z serwerem.',
        error.response?.statusCode,
      );
    }
  }

  Future<String> beginGitHubSignIn({required bool nativeClient}) async {
    final data = await request(
      '/auth/github/start',
      method: 'POST',
      data: {'client': nativeClient ? 'NATIVE' : 'BROWSER'},
      withCredentials: !nativeClient,
    );
    final url = data['authorizationUrl'];
    final state = data['state'];
    if (url is! String || state is! String) {
      throw const ApiException('INVALID_OAUTH_RESPONSE', 'Serwer nie zwrócił linku logowania.');
    }
    await _storage.write(key: _oauthStateKey, value: state);
    return url;
  }

  Future<void> exchangeOAuthHandoff(String code, String state) async {
    final expectedState = await _storage.read(key: _oauthStateKey);
    if (expectedState == null || expectedState != state) {
      throw const ApiException('INVALID_OAUTH_STATE', 'Weryfikacja logowania nie powiodła się. Zaloguj się ponownie.');
    }

    final response = await request(
      '/auth/github/session/exchange',
      method: 'POST',
      data: {'code': code, 'state': state},
    );
    await _storeSession(response);
    await _storage.delete(key: _oauthStateKey);
  }

  Future<void> forgetSession() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _csrfKey);
    await _storage.delete(key: _oauthStateKey);
  }

  Future<String?> currentSession() => _storage.read(key: _sessionKey);
  String get baseUrl => _apiBaseUrl;
}

class ApiException implements Exception {
  const ApiException(this.code, this.message, [this.statusCode]);

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}