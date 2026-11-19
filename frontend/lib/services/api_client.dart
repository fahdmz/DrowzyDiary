import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'env.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.body, {this.retryAfter});

  final int statusCode;
  final String body;
  final Duration? retryAfter;

  bool get isRateLimited => statusCode == 429;
  bool get isUnavailable => statusCode == 503;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class ApiTimeoutException implements Exception {
  ApiTimeoutException(this.path, this.timeout);

  final String path;
  final Duration timeout;

  @override
  String toString() => 'ApiTimeoutException: $path took longer than $timeout';
}

/// Every call to the FastAPI backend goes through here so the
/// Authorization header and base URL are handled in exactly one place —
/// this is the "middleman" between AppState and the network.
class ApiClient {
  ApiClient(
    this._auth, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _timeout = timeout;

  final AuthService _auth;
  final http.Client _client;
  final Duration _timeout;

  Map<String, String> get _headers {
    final token = _auth.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final clean = query?.map((k, v) => MapEntry(k, v));
    return Uri.parse('${Env.apiBaseUrl}$path').replace(queryParameters: clean);
  }

  Future<dynamic> get(String path,
      {Map<String, String>? query, Duration? timeout}) async {
    final res = await _send(
        path, (h) => _client.get(_uri(path, query), headers: h),
        timeout: timeout);
    return _decode(res);
  }

  Future<dynamic> post(String path,
      {Object? body, Map<String, String>? headers, Duration? timeout}) async {
    final res = await _send(
        path,
        (h) => _client.post(_uri(path),
            headers: h, body: body == null ? null : jsonEncode(body)),
        headers: headers,
        timeout: timeout);
    return _decode(res);
  }

  Future<dynamic> patch(String path, {Object? body, Duration? timeout}) async {
    final res = await _send(
        path,
        (h) => _client.patch(_uri(path),
            headers: h, body: body == null ? null : jsonEncode(body)),
        timeout: timeout);
    return _decode(res);
  }

  Future<void> delete(String path, {Duration? timeout}) async {
    final res = await _send(
        path, (h) => _client.delete(_uri(path), headers: h),
        timeout: timeout);
    if (res.statusCode >= 400) throw _exception(res);
  }

  /// Sends with a timeout. On a 401 it refreshes the Supabase session once and
  /// retries once; if the retry is still a 401, the local session is ended so
  /// AppState's auth listener returns the user to the auth screen. [headers]
  /// are sent unchanged on the retry (e.g. the same Idempotency-Key).
  Future<http.Response> _send(
    String path,
    Future<http.Response> Function(Map<String, String> headers) call, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final limit = timeout ?? _timeout;
    Future<http.Response> attempt() => call({..._headers, ...?headers}).timeout(
          limit,
          onTimeout: () => throw ApiTimeoutException(path, limit),
        );

    var res = await attempt();
    if (res.statusCode != 401) return res;

    if (await _auth.refreshSession()) {
      res = await attempt();
      if (res.statusCode != 401) return res;
    }
    await _auth.expireSession();
    return res;
  }

  ApiException _exception(http.Response res) {
    final seconds = int.tryParse(res.headers['retry-after'] ?? '');
    return ApiException(res.statusCode, res.body,
        retryAfter: seconds == null ? null : Duration(seconds: seconds));
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode >= 400) throw _exception(res);
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body);
  }
}
