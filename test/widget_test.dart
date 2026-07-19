import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llb_mobile/src/app.dart';
import 'package:llb_mobile/src/repositories.dart';

void main() {
  testWidgets('shows league home with tournament data', (tester) async {
    await tester.pumpWidget(const LlbApp(repository: MockLeagueRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Лига бильярдистов'), findsOneWidget);
    expect(find.text('Турниры'), findsWidgets);
    expect(find.text('Санкт-Петербург'), findsWidgets);
    expect(find.text('Скоро'), findsOneWidget);
    expect(find.text('Онлайн'), findsOneWidget);
    expect(find.text('Итоги'), findsOneWidget);
    expect(
      find.text('Санкт-Петербург 2026. Ольгино. Пирамида N 30'),
      findsOneWidget,
    );

    await tester.tap(find.text('Итоги'));
    await tester.pumpAndSettle();

    expect(
      find.text('Санкт-Петербург 2026. Ольгино. Пирамида N 28'),
      findsOneWidget,
    );
  });

  testWidgets('opens player details with discipline ЭЛО rows', (tester) async {
    await tester.pumpWidget(const LlbApp(repository: MockLeagueRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Игроки'));
    await tester.pumpAndSettle();
    expect(find.text('РБ'), findsWidgets);
    expect(find.text('Пул'), findsWidgets);

    await tester.tap(find.text('Сергеев Павел'));
    await tester.pumpAndSettle();

    expect(find.text('ЭЛО по дисциплинам'), findsOneWidget);
    expect(find.text('Пул'), findsWidgets);
    expect(find.text('1365'), findsWidgets);
  });

  testWidgets('filters players by selected city', (tester) async {
    await tester.pumpWidget(const LlbApp(repository: MockLeagueRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Игроки'));
    await tester.pumpAndSettle();

    expect(find.text('Санкт-Петербург'), findsWidgets);
    expect(find.text('Сергеев Павел'), findsOneWidget);
    expect(find.text('Игнатьев Олег'), findsNothing);
  });

  testWidgets('sorts players by tournament count', (tester) async {
    await tester.pumpWidget(const LlbApp(repository: MockLeagueRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Игроки'));
    await tester.pumpAndSettle();

    expect(find.text('Турн.'), findsWidgets);
    await tester.tap(find.text('Турн.').first);
    await tester.pumpAndSettle();

    final kalininTop = tester.getTopLeft(find.text('Калинин Андрей')).dy;
    final sergeevTop = tester.getTopLeft(find.text('Сергеев Павел')).dy;
    expect(kalininTop, lessThan(sergeevTop));

    await tester.tap(find.text('Турн.').first);
    await tester.pumpAndSettle();

    final sergeevTopAscending = tester
        .getTopLeft(find.text('Сергеев Павел'))
        .dy;
    final kalininTopAscending = tester
        .getTopLeft(find.text('Калинин Андрей'))
        .dy;
    expect(sergeevTopAscending, lessThan(kalininTopAscending));
  });

  testWidgets('sorts and opens player tournament history', (tester) async {
    await tester.pumpWidget(const LlbApp(repository: MockLeagueRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Игроки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сергеев Павел'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('История участий'), findsOneWidget);
    expect(find.text('Место'), findsOneWidget);

    await tester.tap(find.text('Место'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Санкт-Петербург 2026. Ольгино. Пирамида N 28').last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Турнир'), findsOneWidget);
    expect(
      find.text('Санкт-Петербург 2026. Ольгино. Пирамида N 28'),
      findsWidgets,
    );

    await tester.drag(find.byType(Scrollable), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('Матчи'), findsOneWidget);
    expect(find.text('Финал'), findsOneWidget);
  });

  testWidgets('opens tournament details with participants and matches', (
    tester,
  ) async {
    await tester.pumpWidget(const LlbApp(repository: MockLeagueRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Итоги'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Санкт-Петербург 2026. Ольгино. Пирамида N 28'));
    await tester.pumpAndSettle();

    expect(find.text('Участники'), findsWidgets);
    expect(find.text('Сергеев Павел'), findsWidgets);

    await tester.drag(find.byType(Scrollable), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(find.text('Калинин Андрей'), findsWidgets);

    await tester.drag(find.byType(Scrollable), const Offset(0, -700));
    await tester.pumpAndSettle();

    expect(find.text('Матчи'), findsOneWidget);
    expect(find.text('Финал'), findsOneWidget);
    expect(find.text('4:2'), findsOneWidget);
  });
}
