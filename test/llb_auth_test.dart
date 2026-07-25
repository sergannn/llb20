import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llb_mobile/src/llb_auth.dart';

void main() {
  test(
    'currentPlayerId reads nodeprofile player node instead of random links',
    () async {
      http.Response htmlResponse(String body) => http.Response(
        body,
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );

      final client = LlbWebAuthClient(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          if (request.url.path == '/users/sergannn') {
            return htmlResponse('''
            <body class="logged-in page-users-sergannn">
              <div class="nodeprofile-display">
                <ul class="tabs nodeprofile">
                  <li><a href="/node/4887">Васильев Сергей Юрьевич</a></li>
                  <li><a href="/user/1008/edit/player">Изменить</a></li>
                </ul>
              </div>
            </body>
          ''');
          }
          if (request.url.path == '/') {
            return htmlResponse('''
            <a href="/node/5507410">Новый турнир</a>
            <a href="/node/4887">Васильев Сергей</a>
          ''');
          }
          return htmlResponse('<a href="/node/5507410">Не профиль</a>');
        }),
      );

      expect(await client.currentPlayerId(username: 'sergannn'), '4887');
      client.close();
    },
  );
}
