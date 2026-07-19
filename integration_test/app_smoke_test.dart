import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:llb_mobile/src/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitForHome(WidgetTester tester) async {
    await tester.pumpWidget(const LlbApp());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.text('Турниры').evaluate().isNotEmpty) {
        await tester.pumpAndSettle();
        return;
      }
    }

    fail('Home did not finish loading from live API.');
  }

  testWidgets('live API smoke: tournaments, players and drawer', (
    tester,
  ) async {
    await waitForHome(tester);

    expect(find.text('Лига бильярдистов'), findsOneWidget);
    expect(find.text('Турниры'), findsWidgets);
    expect(find.text('Игроки'), findsOneWidget);
    expect(find.text('Санкт-Петербург'), findsWidgets);
    expect(find.textContaining('Русский'), findsWidgets);
    expect(find.textContaining('API'), findsNothing);

    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Аккаунт LLB'), findsOneWidget);
    expect(find.text('Настройки'), findsWidgets);
    expect(
      find.text('Авторизоваться').evaluate().isNotEmpty ||
          find.text('Выйти').evaluate().isNotEmpty,
      isTrue,
    );
    await tester.tapAt(const Offset(420, 200));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Игроки').last);
    await tester.pumpAndSettle();
    expect(find.text('РБ'), findsWidgets);
    expect(find.text('Пул'), findsWidgets);

    await tester.enterText(find.byType(SearchBar), 'Васильев Сергей');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final player = find.textContaining('Васильев Сергей').first;
    expect(player, findsOneWidget);
    await tester.tap(player);
    await tester.pumpAndSettle();

    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.text('Статистика LLB').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.text('Статистика LLB'), findsOneWidget);
    expect(find.text('387'), findsWidgets);
    expect(find.text('История участий'), findsOneWidget);
    expect(find.textContaining('Zebra - CUP'), findsWidgets);
  });

  testWidgets('live API smoke: upcoming tournament loads participants', (
    tester,
  ) async {
    await waitForHome(tester);

    await tester.enterText(find.byType(SearchBar), 'ТриК3');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final tournament = find.textContaining('ТриК3').first;
    await tester.ensureVisible(tournament);
    await tester.tap(tournament);
    await tester.pumpAndSettle();

    expect(find.text('Участники'), findsWidgets);
    expect(find.text('Список участников не загружен'), findsNothing);
    expect(find.byIcon(Icons.groups_outlined), findsNothing);
  });
}
