import 'dart:convert';

import 'package:http/http.dart' as http;

class LlbLoginResult {
  const LlbLoginResult({
    required this.ok,
    required this.statusCode,
    required this.loggedIn,
    required this.cookies,
    this.error,
  });

  final bool ok;
  final int statusCode;
  final bool loggedIn;
  final Map<String, String> cookies;
  final String? error;
}

class LlbTournamentActionResult {
  const LlbTournamentActionResult({
    required this.ok,
    required this.action,
    required this.message,
    this.error,
  });

  final bool ok;
  final String action;
  final String message;
  final String? error;
}

class AppAuthResult {
  const AppAuthResult({
    required this.id,
    required this.username,
    required this.displayName,
    required this.city,
    required this.token,
  });

  final String id;
  final String username;
  final String displayName;
  final String city;
  final String token;
}

class AppAuthClient {
  AppAuthClient({
    http.Client? client,
    this.apiBaseUrl = const String.fromEnvironment(
      'LLB_API_BASE_URL',
      defaultValue: 'https://llb.panfilius.ru/llb-api/',
    ),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String apiBaseUrl;
  static const _requestTimeout = Duration(seconds: 15);

  Future<AppAuthResult> authenticate({
    required bool register,
    required String username,
    required String password,
    required String displayName,
    required String city,
  }) async {
    final uri = Uri.parse(
      apiBaseUrl,
    ).replace(queryParameters: {'resource': 'app_auth'});
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'action': register ? 'register' : 'login',
            'username': username,
            'password': password,
            'display_name': displayName,
            'city': city,
          }),
        )
        .timeout(_requestTimeout);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('${data['error'] ?? 'app_auth_failed'}');
    }
    final user = (data['user'] as Map<String, dynamic>?) ?? const {};
    return AppAuthResult(
      id: '${user['id'] ?? ''}',
      username: '${user['username'] ?? username}',
      displayName: '${user['display_name'] ?? displayName}',
      city: '${user['city'] ?? city}',
      token: '${user['token'] ?? ''}',
    );
  }

  void close() => _client.close();
}

class LlbWebAuthClient {
  LlbWebAuthClient({
    http.Client? client,
    this.baseUrl = 'https://www.llb.su',
    this.apiBaseUrl = const String.fromEnvironment(
      'LLB_API_BASE_URL',
      defaultValue: 'https://llb.panfilius.ru/llb-api/',
    ),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final String apiBaseUrl;
  final Map<String, String> _cookies = {};
  static const _requestTimeout = Duration(seconds: 15);

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  String get encodedCookies => _cookies.entries
      .map(
        (entry) =>
            '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
      )
      .join('&');

  void loadEncodedCookies(String encoded) {
    _cookies.clear();
    for (final part in encoded.split('&')) {
      if (part.trim().isEmpty) {
        continue;
      }
      final separator = part.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      _cookies[Uri.decodeComponent(part.substring(0, separator))] =
          Uri.decodeComponent(part.substring(separator + 1));
    }
  }

  Future<LlbLoginResult> login({
    required String username,
    required String password,
  }) async {
    try {
      await _send('GET', '/user/login');
      final response = await _send(
        'POST',
        '/user/login?destination=login_redirect',
        body: {
          'name': username,
          'pass': password,
          'form_id': 'user_login',
          'op': 'Войти!',
        },
      );

      var loggedIn = _isLoggedIn(response.body);
      if (!loggedIn) {
        final home = await _send('GET', '/');
        loggedIn =
            _isLoggedIn(home.body) ||
            home.body.toLowerCase().contains(username.toLowerCase());
      }

      return LlbLoginResult(
        ok: response.statusCode >= 200 && response.statusCode < 400 && loggedIn,
        statusCode: response.statusCode,
        loggedIn: loggedIn,
        cookies: cookies,
      );
    } catch (error) {
      return LlbLoginResult(
        ok: false,
        statusCode: 0,
        loggedIn: false,
        cookies: cookies,
        error: '$error',
      );
    }
  }

  Future<bool> sessionValid() async {
    final response = await _send('GET', '/');
    return _isLoggedIn(response.body);
  }

  Future<String?> currentPlayerId({String? username}) async {
    final pages = [await _send('GET', '/'), await _send('GET', '/user')];
    for (final response in pages) {
      final id = _extractPlayerId(response.body, username: username);
      if (id != null) {
        return id;
      }
    }
    return null;
  }

  Future<void> saveVerifiedCredentialsToServer({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse(
      apiBaseUrl,
    ).replace(queryParameters: {'resource': 'llb_auth'});
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('LLB API auth save HTTP ${response.statusCode}');
    }
  }

  Future<LlbTournamentActionResult> directTournamentRegistrationAction({
    required String tournamentId,
    required String action,
  }) async {
    final normalizedAction = action == 'unregister' ? 'unregister' : 'register';
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        final response = await _send(
          'POST',
          '/node/$tournamentId',
          body: normalizedAction == 'register'
              ? {'register': 'yes', 'agree': 'ok'}
              : {'unregister': 'yes'},
        );
        final loggedIn = _isLoggedIn(response.body);
        final ok =
            response.statusCode >= 200 && response.statusCode < 400 && loggedIn;
        return LlbTournamentActionResult(
          ok: ok,
          action: normalizedAction,
          message: ok
              ? (normalizedAction == 'register'
                    ? 'Заявка отправлена в LLB.'
                    : 'Регистрация отменена в LLB.')
              : 'LLB не подтвердил действие. Возможно, сессия истекла.',
          error: ok ? null : 'llb_action_failed',
        );
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
      }
    }
    return LlbTournamentActionResult(
      ok: false,
      action: normalizedAction,
      message:
          'Связь с LLB оборвалась. Обновите турнир и попробуйте действие еще раз.',
      error: lastError?.toString() ?? 'llb_connection_failed',
    );
  }

  void close() => _client.close();

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? body,
  }) async {
    var currentMethod = method;
    var currentUri = Uri.parse('$baseUrl$path');
    var currentBody = body;

    for (var redirect = 0; redirect < 8; redirect += 1) {
      final response = await _sendOnce(
        currentMethod,
        currentUri,
        body: currentBody,
      );
      if (!_isRedirect(response.statusCode)) {
        return response;
      }

      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        return response;
      }
      currentUri = currentUri.resolve(location);
      if (response.statusCode == 303 ||
          ((response.statusCode == 301 || response.statusCode == 302) &&
              currentMethod != 'GET')) {
        currentMethod = 'GET';
        currentBody = null;
      }
    }

    throw StateError('Too many LLB redirects');
  }

  Future<http.Response> _sendOnce(
    String method,
    Uri uri, {
    Map<String, String>? body,
  }) async {
    final request = http.Request(method, uri);
    request.followRedirects = false;
    request.headers.addAll({
      'User-Agent': 'Mozilla/5.0 (compatible; llb-mobile/1.0)',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    });
    if (_cookies.isNotEmpty) {
      request.headers['Cookie'] = _cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/x-www-form-urlencoded';
      request.bodyFields = body;
    }

    final streamed = await _client.send(request).timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamed);
    _storeCookies(response.headers['set-cookie']);
    return response;
  }

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  void _storeCookies(String? rawSetCookie) {
    if (rawSetCookie == null || rawSetCookie.isEmpty) {
      return;
    }
    final parts = rawSetCookie.split(RegExp(r',\s*(?=[^;,]+=)'));
    for (final part in parts) {
      final first = part.split(';').first.trim();
      final separator = first.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      _cookies[first.substring(0, separator)] = first.substring(separator + 1);
    }
  }

  bool _isLoggedIn(String html) {
    return !html.contains('not-logged-in') &&
        (html.contains('/user/logout') ||
            html.contains('/logout') ||
            html.contains('Выйти'));
  }

  String? _extractPlayerId(String html, {String? username}) {
    final patterns = <RegExp>[
      RegExp(r"""href=["']/(?:node|user)/(\d+)["']"""),
      RegExp(r"""href=["']https?://www\.llb\.su/(?:node|user)/(\d+)["']"""),
    ];
    final normalizedUsername = username?.trim().toLowerCase();
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        final id = match.group(1);
        if (id == null || id.isEmpty) {
          continue;
        }
        if (normalizedUsername == null || normalizedUsername.isEmpty) {
          return id;
        }
        final start = (match.start - 220).clamp(0, html.length);
        final end = (match.end + 220).clamp(0, html.length);
        final nearby = html.substring(start, end).toLowerCase();
        if (nearby.contains(normalizedUsername) ||
            nearby.contains('мой профиль') ||
            nearby.contains('личн')) {
          return id;
        }
      }
    }
    return null;
  }
}
