import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llb_mobile/src/models.dart';
import 'package:llb_mobile/src/repositories.dart';

void main() {
  test('loads current LLB profile by node id with discipline ЭЛО', () async {
    final repository = ApiLeagueRepository(
      baseUri: 'https://example.test/llb-api/',
      client: MockClient((request) async {
        expect(request.url.queryParameters['resource'], 'player');
        expect(request.url.queryParameters['id'], '4887');

        return http.Response(
          jsonEncode({
            'id': 4887,
            'name': 'Васильев Сергей',
            'city': 'Санкт-Петербург',
            'country': 'Россия',
            'avatar_url': 'https://www.llb.su/files/vasiliev_sergey.jpg',
            'elo': 930,
            'ratings': [
              {
                'rating_key': 'llb-spyramid',
                'discipline': 'ЛЛБ - пирамида (любым шаром)',
                'rating_label': 'Рейтинг Эло',
                'elo': 930,
                'comps_total': 115,
              },
              {
                'rating_key': 'llb-pool',
                'discipline': 'ЛЛБ - пул',
                'rating_label': 'Рейтинг Эло',
                'elo': 894,
                'comps_total': 3,
              },
              {
                'rating_key': 'llb-pyramid',
                'discipline': 'ЛЛБ - пирамида (одним шаром)',
                'rating_label': 'Рейтинг Эло',
                'elo': null,
                'comps_total': 212,
              },
            ],
            'stats': {'total': 387, 'pyramid': 381, 'pool': 5, 'snooker': 1},
            'tournament_entries': [
              {
                'tournament_id': 5191137,
                'title': 'Санкт-Петербург 2025. Турнир «Zebra - CUP 6»',
                'date_text': '10.04.2025 - 09.07.2025',
                'points': '',
                'place': '56',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final player = await repository.playerById('4887');

    expect(player?.id, '4887');
    expect(player?.name, 'Васильев Сергей');
    expect(player?.russianBilliardsElo, 930);
    expect(player?.poolElo, 894);
    expect(player?.avatarUrl, contains('vasiliev_sergey.jpg'));
    expect(player?.stats.total, 387);
    expect(player?.stats.pyramid, 381);
    expect(
      player?.ratings.map((rating) => rating.discipline),
      containsAll(['Пирамида (любым шаром)', 'Пирамида (одним шаром)']),
    );
    expect(
      player?.ratings
          .where((rating) => rating.key == 'llb-pyramid')
          .single
          .compsTotal,
      212,
    );
    expect(player?.tournamentEntries.single.tournamentId, '5191137');
  });

  test('loads player detail even when player exists in cached list', () async {
    final repository = ApiLeagueRepository(
      baseUri: 'https://example.test/llb-api/',
      client: MockClient((request) async {
        final resource = request.url.queryParameters['resource'];
        if (resource == 'players') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 171085,
                  'name': 'Мансуров Сергей',
                  'city': 'Йошкар-Ола',
                  'country': 'Россия',
                  'best_elo': 1700,
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (resource == 'tournaments') {
          return http.Response(
            jsonEncode({'items': []}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (resource == 'video_streams') {
          return http.Response(
            jsonEncode({'items': []}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        expect(resource, 'player');
        expect(request.url.queryParameters['id'], '171085');
        return http.Response(
          jsonEncode({
            'id': 171085,
            'name': 'Мансуров Сергей',
            'city': 'Йошкар-Ола',
            'country': 'Россия',
            'best_elo': 1700,
            'tournament_entries': [
              {
                'tournament_id': 5447543,
                'title': '3-й Кубок Раиса Республики Татарстан',
                'date_text': '31.03.26',
                'points': '',
                'place': '33 - 48',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await repository.load();
    final player = await repository.playerById('171085');

    expect(player?.name, 'Мансуров Сергей');
    expect(player?.tournamentEntries, hasLength(1));
    expect(player?.tournamentEntries.single.tournamentId, '5447543');
  });

  test('loads tournaments for each status bucket', () async {
    final requestedStatuses = <String>[];
    final repository = ApiLeagueRepository(
      baseUri: 'https://example.test/llb-api/',
      client: MockClient((request) async {
        final resource = request.url.queryParameters['resource'];
        if (resource == 'players') {
          return http.Response(jsonEncode({'items': []}), 200);
        }
        if (resource == 'video_streams') {
          return http.Response(jsonEncode({'items': []}), 200);
        }
        expect(resource, 'tournaments');
        final status = request.url.queryParameters['status'];
        requestedStatuses.add(status ?? '');
        final sourceKind = switch (status) {
          'upcoming' => 'next',
          'online' => 'online',
          'finished' => 'results',
          _ => '',
        };
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'items': [
                {
                  'id': status == 'finished'
                      ? 3
                      : status == 'online'
                      ? 2
                      : 1,
                  'title': 'Санкт-Петербург 2026. Турнир $status',
                  'source_kind': sourceKind,
                  'status_class': status == 'upcoming' ? 'future' : 'online',
                  'date_text': '01.01.26',
                  'club': 'Клуб',
                  'participants_count': 1,
                  'matches_count': 0,
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await repository.load();

    expect(requestedStatuses, containsAll(['upcoming', 'online', 'finished']));
    expect(
      repository.tournaments().map((tournament) => tournament.status),
      contains(TournamentStatus.finished),
    );
  });

  test(
    'keeps archive participant place and points from tournament API',
    () async {
      final repository = ApiLeagueRepository(
        baseUri: 'https://example.test/llb-api/',
        client: MockClient((request) async {
          final resource = request.url.queryParameters['resource'];
          if (resource == 'players') {
            return http.Response(jsonEncode({'items': []}), 200);
          }
          if (resource == 'tournaments') {
            return http.Response(jsonEncode({'items': []}), 200);
          }
          expect(resource, 'tournament');
          expect(request.url.queryParameters['id'], '2335');
          return http.Response(
            jsonEncode({
              'id': 2335,
              'title': 'ЛЛБ 2009. Санкт-Петербург. Пирамида № 3',
              'source_kind': 'archive',
              'participants_count': 1,
              'participants': [
                {
                  'membership_node_id': 47036,
                  'name': 'Смоляр Виктор Викторович',
                  'points': '383',
                  'place': '2',
                },
              ],
              'matches': [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final tournament = await repository.tournamentDetails(
        const Tournament(
          id: '2335',
          title: 'ЛЛБ 2009. Санкт-Петербург. Пирамида № 3',
          city: 'Санкт-Петербург',
          club: '',
          discipline: 'Пирамида',
          level: '',
          dateLabel: '',
          playersCount: 0,
          capacity: null,
          matchesCount: 0,
          status: TournamentStatus.finished,
          bracketUrl: 'https://www.llb.su/node/2335',
          players: [],
          matches: [],
        ),
      );

      final participant = tournament.players.single;
      expect(participant.hasRealLlbId, isFalse);
      expect(participant.membershipNodeId, '47036');
      expect(participant.participantPoints, '383');
      expect(participant.participantPlace, '2');
      expect(participant.participantSummary, 'место: 2 · очки: 383');
    },
  );
}
