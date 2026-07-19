import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/repositories.dart';

void main() {
  const useMockData = bool.fromEnvironment('LLB_USE_MOCK_DATA');
  runApp(LlbApp(repository: useMockData ? const MockLeagueRepository() : null));
}
