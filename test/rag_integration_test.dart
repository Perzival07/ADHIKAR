import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqdaar/core/models/citizen_profile.dart';
import 'package:haqdaar/core/services/recommendation_api_client.dart';
import 'package:haqdaar/core/services/recommendation_repository.dart';
import 'package:haqdaar/core/services/scheme_engine.dart';
import 'package:haqdaar/core/services/settings_service.dart';
import 'package:haqdaar/screens/results/schemes_result_screen.dart';
import 'package:haqdaar/screens/wizard/adaptive_wizard_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

CitizenProfile farmer() => CitizenProfile(
      state: 'Uttar Pradesh',
      age: 40,
      gender: 'Male',
      occupation: 'Farmer',
      landHoldingAcres: 2.0,
      socialCategory: 'OBC',
      rationCard: 'BPL',
      annualIncomeRange: '< 1 Lakh',
    );

Map<String, dynamic> rec(String id, int rank, String reason,
        {String status = 'eligible', List<String> missing = const [], List<Map<String, dynamic>>? cites}) =>
    {
      'scheme_id': id,
      'name': id,
      'rank': rank,
      'confidence': 0.9,
      'reason': reason,
      'reason_language': 'en',
      'citations': cites ??
          [
            {'chunk_id': 'c-$id', 'quote': '', 'section': 'Benefit', 'url': 'https://example.gov.in/$id'}
          ],
      'missing_info': missing,
      'eligibility_status': status,
    };

http.Response json200(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> ragBody(List<Map<String, dynamic>> recs, {String mode = 'rag', String? fallback}) => {
      'recommendations': recs,
      'more': [],
      'mode': mode,
      'trace_id': 't',
      'fallback_reason': fallback,
    };

RecommendationApiClient apiWith(MockClientHandler h, {Duration timeout = const Duration(seconds: 5)}) =>
    RecommendationApiClient(baseUrl: 'http://api.test', client: MockClient(h), timeout: timeout);

void main() {
  group('RecommendationApiClient', () {
    test('posts only the citizen profile fields (never name/phone/email) with a request id', () async {
      late http.Request seen;
      final api = apiWith((req) async {
        seen = req;
        return json200(ragBody([rec('pm_kisan', 1, 'because')]));
      });
      final res = await api.recommend(farmer(), language: 'hi', topN: 6);

      expect(seen.url.toString(), 'http://api.test/v1/recommendations');
      expect(seen.headers['X-Request-ID'], matches(RegExp(r'^[0-9a-f]{32}$')));
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {'profile', 'language', 'top_n', 'include_citations'});
      expect(body['profile'], farmer().toJson());
      expect((body['profile'] as Map).keys.toSet(), CitizenProfile().toJson().keys.toSet());
      final raw = seen.body.toLowerCase();
      for (final forbidden in ['"name"', 'phone', 'email', 'password']) {
        expect(raw.contains(forbidden), false, reason: forbidden);
      }
      expect(body['language'], 'hi');
      expect(res.isAi, true);
      expect(res.recommendations.single.citations.single.section, 'Benefit');
    });

    test('trailing slashes in the base URL are tolerated', () async {
      late Uri url;
      final api = RecommendationApiClient(
        baseUrl: 'http://api.test///',
        client: MockClient((r) async {
          url = r.url;
          return json200(ragBody([]));
        }),
      );
      await api.recommend(farmer());
      expect(url.toString(), 'http://api.test/v1/recommendations');
    });

    test('non-200, malformed JSON, wrong shape, network error and timeout all become RecommendationApiException', () async {
      Future<void> expectFails(MockClientHandler h, {Duration? timeout, int? status}) async {
        final api = apiWith(h, timeout: timeout ?? const Duration(seconds: 5));
        try {
          await api.recommend(farmer());
          fail('expected an exception');
        } on RecommendationApiException catch (e) {
          if (status != null) expect(e.statusCode, status);
        }
      }

      await expectFails((r) async => http.Response('{"detail":"busy"}', 503), status: 503);
      await expectFails((r) async => http.Response('not json', 200));
      await expectFails((r) async => json200({'recommendations': 'nope'}));
      await expectFails((r) async => throw http.ClientException('connection refused'));
      await expectFails((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return json200(ragBody([]));
      }, timeout: const Duration(milliseconds: 20));
    });

    test('unconfigured client refuses to call out', () async {
      var called = false;
      final api = RecommendationApiClient(baseUrl: '', client: MockClient((r) async {
        called = true;
        return json200(ragBody([]));
      }));
      expect(api.isConfigured, false);
      await expectLater(api.recommend(farmer()), throwsA(isA<RecommendationApiException>()));
      expect(called, false);
    });
  });

  group('RecommendationRepository', () {
    RecommendationRepository repoWith(MockClientHandler h) => RecommendationRepository(api: apiWith(h));

    test('AI disabled -> pure on-device rules, no network call', () async {
      var calls = 0;
      final repo = repoWith((r) async {
        calls++;
        return json200(ragBody([]));
      });
      final res = await repo.recommend(farmer(), language: 'en', aiEnabled: false);
      expect(calls, 0);
      expect(res.mode, RecommendationMode.ruleBased);
      expect(res.schemes.map((s) => s.id), SchemeEngine.evaluate(farmer()).map((s) => s.id));
    });

    test('no client at all (offline build) -> rule-based', () async {
      final res = await RecommendationRepository().recommend(farmer(), language: 'en', aiEnabled: true);
      expect(res.mode, RecommendationMode.ruleBased);
      expect(res.schemes, isNotEmpty);
    });

    test('success: AI order first, extras attached, local schemes the AI skipped are appended', () async {
      final localIds = SchemeEngine.evaluate(farmer()).map((s) => s.id).toList();
      expect(localIds, contains('pm_kisan'));
      final repo = repoWith((r) async => json200(ragBody([
            rec('ayushman_bharat', 1, 'Health cover for your family.'),
            rec('pm_kisan', 2, 'Income support because you farm.'),
          ])));
      final res = await repo.recommend(farmer(), language: 'en', aiEnabled: true);
      expect(res.mode, RecommendationMode.aiAssisted);
      expect(res.schemes.map((s) => s.id).take(2), ['ayushman_bharat', 'pm_kisan']);
      expect(res.extras['pm_kisan']!.reason, 'Income support because you farm.');
      expect(res.extras['pm_kisan']!.citations.single.url, 'https://example.gov.in/pm_kisan');
      expect(res.schemes.map((s) => s.id).toSet(), localIds.toSet()); // nothing lost, nothing duplicated
      expect(res.schemes.length, localIds.length);
      expect(res.extras.containsKey(res.schemes.last.id), false); // appended local ones have no AI text
    });

    test('hallucinated scheme ids and empty reasons from the server are ignored', () async {
      final repo = repoWith((r) async => json200(ragBody([
            rec('totally_made_up', 1, 'invented'),
            rec('pm_kisan', 2, '   '),
            rec('ayushman_bharat', 3, 'Real one.'),
            rec('ayushman_bharat', 4, 'Duplicate.'),
          ])));
      final res = await repo.recommend(farmer(), language: 'en', aiEnabled: true);
      expect(res.extras.keys, ['ayushman_bharat']);
      expect(res.extras['ayushman_bharat']!.reason, 'Real one.');
      expect(res.schemes.any((s) => s.id == 'totally_made_up'), false);
    });

    test('only hallucinated ids -> falls back to rules', () async {
      final repo = repoWith((r) async => json200(ragBody([rec('nope', 1, 'x')])));
      final res = await repo.recommend(farmer(), language: 'en', aiEnabled: true);
      expect(res.mode, RecommendationMode.ruleBased);
      expect(res.fallbackReason, 'no_valid_ai_items');
    });

    test('unknown eligibility + missing info are surfaced', () async {
      final repo = repoWith((r) async => json200(ragBody([
            rec('pm_kisan', 1, 'Maybe.', status: 'unknown', missing: ['Land ownership record']),
          ])));
      final res = await repo.recommend(farmer(), language: 'en', aiEnabled: true);
      expect(res.extras['pm_kisan']!.needsMoreInfo, true);
      expect(res.extras['pm_kisan']!.missingInfo, ['Land ownership record']);
    });

    test('backend errors and server-side rules_only fall back to on-device rules', () async {
      final down = await repoWith((r) async => http.Response('boom', 503)).recommend(farmer(), language: 'en', aiEnabled: true);
      expect(down.mode, RecommendationMode.ruleBased);
      expect(down.fallbackReason, 'unexpected response');
      expect(down.schemes.map((s) => s.id), SchemeEngine.evaluate(farmer()).map((s) => s.id));

      final net = await repoWith((r) async => throw http.ClientException('x')).recommend(farmer(), language: 'en', aiEnabled: true);
      expect(net.mode, RecommendationMode.ruleBased);
      expect(net.fallbackReason, startsWith('network error'));

      final rules = await repoWith((r) async => json200(ragBody([rec('pm_kisan', 1, 'r')], mode: 'rules_only', fallback: 'llm_503')))
          .recommend(farmer(), language: 'en', aiEnabled: true);
      expect(rules.mode, RecommendationMode.ruleBased);
      expect(rules.fallbackReason, 'llm_503');
      expect(rules.extras, isEmpty);
    });
  });

  group('Results screen', () {
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsService(aiAvailableOverride: true);
      await settings.init();
    });

    Future<void> pump(WidgetTester tester, RecommendationRepository repo) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final profile = farmer();
      await tester.pumpWidget(MaterialApp(
        home: SchemesResultScreen(
          profile: profile,
          eligibleSchemes: SchemeEngine.evaluate(profile),
          settings: settings,
          repository: repo,
        ),
      ));
    }

    testWidgets('shows rule-based instantly, then upgrades to AI-assisted with reasons and source chips', (tester) async {
      final gate = Completer<void>();
      final repo = RecommendationRepository(
        api: apiWith((r) async {
          await gate.future;
          return json200(ragBody([
            rec('pm_kisan', 1, 'AI says: you farm 2 acres, so you get income support.'),
          ]));
        }),
      );
      await pump(tester, repo);
      await tester.pump();
      expect(find.byKey(const Key('mode_badge_loading')), findsOneWidget);
      expect(find.textContaining('PM-KISAN'), findsWidgets); // rule-based list is already on screen

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mode_badge')), findsOneWidget);
      expect(find.text('AI-assisted'), findsOneWidget);
      expect(find.textContaining('AI says: you farm 2 acres'), findsOneWidget);
      expect(find.byKey(const Key('sources_pm_kisan')), findsOneWidget);
      expect(find.text('Benefit'), findsOneWidget);
    });

    testWidgets('backend down -> Rule-based badge and normal results', (tester) async {
      final repo = RecommendationRepository(api: apiWith((r) async => throw http.ClientException('refused')));
      await pump(tester, repo);
      await tester.pumpAndSettle();
      expect(find.text('Rule-based'), findsOneWidget);
      expect(find.text('AI-assisted'), findsNothing);
      expect(find.byKey(const Key('mode_badge_loading')), findsNothing);
      expect(find.textContaining('PM-KISAN'), findsWidgets);
    });

    testWidgets('AI turned off in settings -> never calls the backend', (tester) async {
      await settings.setAiRecommendationsEnabled(false);
      var calls = 0;
      final repo = RecommendationRepository(api: apiWith((r) async {
        calls++;
        return json200(ragBody([]));
      }));
      await pump(tester, repo);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Rule-based'), findsOneWidget);
    });

    testWidgets('missing-info prompt offers to go back to the wizard with answers pre-filled', (tester) async {
      final repo = RecommendationRepository(
        api: apiWith((r) async => json200(ragBody([
              rec('pm_kisan', 1, 'Likely, but we need one more thing.', status: 'unknown', missing: ['Land ownership record (Khatauni)']),
            ]))),
      );
      await pump(tester, repo);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('missing_pm_kisan')), findsOneWidget);
      expect(find.textContaining('Land ownership record (Khatauni)'), findsOneWidget);

      await tester.ensureVisible(find.text('Update my answers'));
      await tester.tap(find.text('Update my answers'));
      await tester.pumpAndSettle();
      expect(find.byType(AdaptiveWizardScreen), findsOneWidget);
      final wizard = tester.widget<AdaptiveWizardScreen>(find.byType(AdaptiveWizardScreen));
      expect(wizard.initialProfile!.occupation, 'Farmer');
      expect(wizard.initialProfile!.landHoldingAcres, 2.0);
    });
    testWidgets('changing the language re-fetches AI reasons in the new language (stale answers are ignored)', (tester) async {
      final languages = <String>[];
      final repo = RecommendationRepository(
        api: apiWith((r) async {
          final lang = jsonDecode(r.body)['language'] as String;
          languages.add(lang);
          return json200(ragBody([rec('pm_kisan', 1, 'reason in $lang')]));
        }),
      );
      await pump(tester, repo);
      await tester.pumpAndSettle();
      expect(find.textContaining('reason in en'), findsOneWidget);

      await settings.setLanguage('hi');
      await tester.pumpAndSettle();
      expect(languages, ['en', 'hi']);
      expect(find.textContaining('reason in hi'), findsOneWidget);
      expect(find.textContaining('reason in en'), findsNothing);
    });

    testWidgets('turning AI off drops AI text; turning it on again fetches again', (tester) async {
      var calls = 0;
      final repo = RecommendationRepository(
        api: apiWith((r) async {
          calls++;
          return json200(ragBody([rec('pm_kisan', 1, 'AI reason $calls')]));
        }),
      );
      await pump(tester, repo);
      await tester.pumpAndSettle();
      expect(find.text('AI-assisted'), findsOneWidget);

      await settings.setAiRecommendationsEnabled(false);
      await tester.pumpAndSettle();
      expect(find.text('Rule-based'), findsOneWidget);
      expect(find.textContaining('AI reason'), findsNothing);

      await settings.setAiRecommendationsEnabled(true);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('AI-assisted'), findsOneWidget);
    });

    testWidgets('an answer that arrives after a language change is discarded', (tester) async {
      final gates = <String, Completer<void>>{'en': Completer(), 'hi': Completer()};
      final repo = RecommendationRepository(
        api: apiWith((r) async {
          final lang = jsonDecode(r.body)['language'] as String;
          await gates[lang]!.future;
          return json200(ragBody([rec('pm_kisan', 1, 'reason in $lang')]));
        }),
      );
      await pump(tester, repo);
      await tester.pump();
      await settings.setLanguage('hi'); // second request starts while the first is still pending
      await tester.pump();
      gates['hi']!.complete();
      await tester.pumpAndSettle();
      gates['en']!.complete(); // the stale English answer finally arrives
      await tester.pumpAndSettle();
      expect(find.textContaining('reason in hi'), findsOneWidget);
      expect(find.textContaining('reason in en'), findsNothing);
    });
  });

  group('SettingsService AI toggle', () {
    test('available only when a backend is configured; default on; persists', () async {
      SharedPreferences.setMockInitialValues({});
      final off = SettingsService(aiAvailableOverride: false);
      await off.init();
      expect(off.aiRecommendationsAvailable, false);
      expect(off.aiRecommendationsEnabled, false);

      final on = SettingsService(aiAvailableOverride: true);
      await on.init();
      expect(on.aiRecommendationsEnabled, true);
      await on.setAiRecommendationsEnabled(false);
      expect(on.aiRecommendationsEnabled, false);

      final again = SettingsService(aiAvailableOverride: true);
      await again.init();
      expect(again.aiRecommendationsEnabled, false); // persisted
    });
  });
}
