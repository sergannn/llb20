import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main() async {
  final username = Platform.environment['LLB_USERNAME'] ?? '';
  final password = Platform.environment['LLB_PASSWORD'] ?? '';
  if (username.isEmpty || password.isEmpty) {
    stderr.writeln('Set LLB_USERNAME and LLB_PASSWORD.');
    exitCode = 2;
    return;
  }

  final client = http.Client();
  final cookies = <String, String>{};

  Future<http.Response> send(
    String method,
    String path, {
    Map<String, String>? body,
  }) async {
    var uri = Uri.parse('https://www.llb.su$path');
    var currentMethod = method;
    var currentBody = body;
    for (var i = 0; i < 8; i += 1) {
      final request = http.Request(currentMethod, uri);
      request.followRedirects = false;
      request.headers['User-Agent'] =
          'Mozilla/5.0 (compatible; llb-mobile-probe/1.0)';
      request.headers['Accept'] =
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
      if (cookies.isNotEmpty) {
        request.headers['Cookie'] = cookies.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join('; ');
      }
      if (currentBody != null) {
        request.bodyFields = currentBody;
      }
      final response = await http.Response.fromStream(
        await client.send(request),
      );
      final rawSetCookie = response.headers['set-cookie'];
      storeCookies(cookies, response.headers['set-cookie']);
      stdout.writeln(
        '$currentMethod $uri -> ${response.statusCode} '
        'location=${response.headers['location'] ?? '-'} '
        'cookies=${cookies.entries.map((entry) => '${entry.key}:${entry.value.length}').join(',')} '
        'setCookie=${maskSetCookie(rawSetCookie)}',
      );
      if (response.statusCode < 300 || response.statusCode >= 400) {
        return response;
      }
      final location = response.headers['location'];
      if (location == null || location.isEmpty) {
        return response;
      }
      uri = uri.resolve(location);
      if (response.statusCode == 303 ||
          ((response.statusCode == 301 || response.statusCode == 302) &&
              currentMethod != 'GET')) {
        currentMethod = 'GET';
        currentBody = null;
      }
    }
    throw StateError('Too many redirects');
  }

  final loginPage = await send('GET', '/user/login');
  printSignals('login page', loginPage.body, username);

  final post = await send(
    'POST',
    '/user/login?destination=login_redirect',
    body: {
      'name': username,
      'pass': password,
      'form_id': 'user_login',
      'op': 'Войти!',
    },
  );
  printSignals('post result', post.body, username);

  final home = await send('GET', '/');
  printSignals('home', home.body, username);

  client.close();
}

String maskSetCookie(String? raw) {
  if (raw == null || raw.isEmpty) {
    return '-';
  }
  return raw.replaceAllMapped(
    RegExp(r'(SESS[^=]*=)[^;,\s]+'),
    (match) => '${match.group(1)}***',
  );
}

void storeCookies(Map<String, String> cookies, String? rawSetCookie) {
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
    cookies[first.substring(0, separator)] = first.substring(separator + 1);
  }
}

void printSignals(String label, String html, String username) {
  final lower = html.toLowerCase();
  stdout.writeln(
    '$label signals: logout=${html.contains('/user/logout') || html.contains('/logout')} '
    'notLoggedIn=${html.contains('not-logged-in')} '
    'username=${lower.contains(username.toLowerCase())} '
    'error=${lower.contains('error') || lower.contains('ошиб')}',
  );
  final title = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html)?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (title != null) {
    stdout.writeln('$label title: $title');
  }
}
