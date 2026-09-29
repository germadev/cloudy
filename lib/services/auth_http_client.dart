import 'dart:async';

import 'package:http/http.dart' as http;

/// Obtiene y cachea tokens de acceso OAuth. Los tokens de Google caducan a la
/// hora, así que se renuevan antes para no fallar en sincronizaciones largas.
class AccessTokenProvider {
  AccessTokenProvider(
    this._fetch, {
    this.onInvalidate,
    this.maxAge = const Duration(minutes: 45),
  });

  final Future<String> Function() _fetch;
  final Future<void> Function(String token)? onInvalidate;
  final Duration maxAge;

  String? _token;
  DateTime? _fetchedAt;
  Future<String>? _pending;

  Future<String> token() {
    final token = _token;
    final fetchedAt = _fetchedAt;
    if (token != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < maxAge) {
      return Future.value(token);
    }
    return _pending ??= _fetch()
        .then((value) {
          _token = value;
          _fetchedAt = DateTime.now();
          return value;
        })
        .whenComplete(() => _pending = null);
  }

  /// Descarta el token actual (p. ej. tras un 401) para pedir otro.
  Future<void> invalidate() async {
    final token = _token;
    _token = null;
    _fetchedAt = null;
    if (token != null) await onInvalidate?.call(token);
  }
}

/// Cliente HTTP que añade la cabecera de autorización a cada petición.
class AuthHttpClient extends http.BaseClient {
  AuthHttpClient(this._tokens, [http.Client? inner])
    : _inner = inner ?? http.Client();

  final AccessTokenProvider _tokens;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] = 'Bearer ${await _tokens.token()}';
    final response = await _inner.send(request);
    if (response.statusCode == 401) {
      // La siguiente petición (el reintento) usará un token nuevo.
      await _tokens.invalidate();
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
