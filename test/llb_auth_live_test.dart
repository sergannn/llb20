import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llb_mobile/src/llb_auth.dart';

void main() {
  test(
    'logs in to llb.su with a real web session',
    () async {
      final username = Platform.environment['LLB_USERNAME'] ?? '';
      final password = Platform.environment['LLB_PASSWORD'] ?? '';
      if (username.isEmpty || password.isEmpty) {
        markTestSkipped(
          'Set LLB_USERNAME and LLB_PASSWORD to run live auth test.',
        );
        return;
      }

      final client = LlbWebAuthClient();
      addTearDown(client.close);

      final result = await client.login(username: username, password: password);

      expect(result.error, isNull);
      expect(result.statusCode, inInclusiveRange(200, 399));
      expect(result.cookies, isNotEmpty);
      expect(result.loggedIn, isTrue);
      expect(result.ok, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
