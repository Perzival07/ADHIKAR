import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:haqdaar/core/models/citizen_profile.dart';
import 'package:haqdaar/core/services/auth_api_client.dart';
import 'package:haqdaar/core/services/auth_service.dart';
import 'package:haqdaar/core/services/recommendation_api_client.dart';
import 'package:haqdaar/core/services/token_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for backend/services/auth-service with the same rules that matter to the app:
/// codes are emailed by the server, refresh tokens rotate and are single-use, logout revokes.
class FakeAuthServer {
  final requests = <http.Request>[];
  final codes = <String, String>{}; // email -> last code "sent"
  final users = <String, Map<String, dynamic>>{}; // email -> user + password
  final liveRefresh = <String, String>{}; // refresh token -> email
  final liveAccess = <String, String>{}; // access token -> email
  int _n = 0;
  bool offline = false;

  Map<String, dynamic> _pair(String email) {
    final access = 'acc-${++_n}';
    final refresh = 'ref-${++_n}-${'x' * 30}';
    liveAccess[access] = email;
    liveRefresh[refresh] = email;
    final u = users[email]!;
    return {
      'access_token': access, 'token_type': 'bearer', 'expires_in': 900, 'refresh_token': refresh,
      'refresh_expires_in': 2592000,
      'user': {
        'id': u['id'], 'email': email, 'phone': null, 'name': u['name'], 'state': u['state'],
        'socialCategory': 'General', 'occupation': 'Citizen', 'profile': null, 'isVerified': true,
        'createdAt': '2026-11-10T00:00:00Z',
      },
    };
  }

  http.Response _json(int status, Object body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  Future<http.Response> call(http.Request r) async {
    requests.add(r);
    if (offline) throw http.ClientException('offline');
    final body = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    final bearer = (r.headers['authorization'] ?? '').replaceFirst('Bearer ', '');
    switch ('${r.method} ${r.url.path}') {
      case 'POST /v1/auth/otp/request':
        codes[body['email'] as String] = '123456';
        return _json(202, {'status': 'accepted', 'message': '', 'resend_after': 60});
      case 'POST /v1/auth/signup':
        if (codes[body['email']] != body['code']) return _json(400, {'detail': 'The code is invalid or has expired. Request a new one.'});
        users[body['email'] as String] = {'id': 'u-${users.length + 1}', 'name': body['name'], 'state': body['state'], 'password': body['password']};
        return _json(201, _pair(body['email'] as String));
      case 'POST /v1/auth/login':
        final u = users[body['identifier']];
        if (u == null || u['password'] != body['password']) return _json(401, {'detail': 'Invalid credentials.'});
        return _json(200, _pair(body['identifier'] as String));
      case 'POST /v1/auth/login/otp':
        if (codes[body['email']] != body['code'] || !users.containsKey(body['email'])) {
          return _json(400, {'detail': 'The code is invalid or has expired. Request a new one.'});
        }
        return _json(200, _pair(body['email'] as String));
      case 'POST /v1/auth/token/refresh':
        final email = liveRefresh.remove(body['refresh_token']); // single use
        if (email == null) return _json(401, {'detail': 'Invalid credentials.'});
        return _json(200, _pair(email));
      case 'POST /v1/auth/logout':
        liveRefresh.remove(body['refresh_token']);
        return http.Response('', 204);
      case 'PATCH /v1/users/me':
        final email = liveAccess[bearer];
        if (email == null) return _json(401, {'detail': 'Invalid or expired token.'});
        users[email]!.addAll({if (body['name'] != null) 'name': body['name'], if (body['state'] != null) 'state': body['state']});
        return _json(200, (_pair(email)['user'] as Map<String, dynamic>));
      case 'DELETE /v1/users/me':
        final email = liveAccess[bearer];
        if (email == null) return _json(401, {'detail': 'Invalid or expired token.'});
        users.remove(email);
        liveRefresh.removeWhere((_, e) => e == email);
        return http.Response('', 204);
    }
    return _json(404, {'detail': 'Not Found'});
  }
}

void main() {
  late FakeAuthServer server;
  late MemoryTokenStore tokens;

  AuthService newAuth() => AuthService(
        api: AuthApiClient(baseUrl: 'http://auth.test', client: MockClient(server.call)),
        tokenStore: tokens,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = FakeAuthServer();
    tokens = MemoryTokenStore();
  });

  Future<AuthService> signedUp() async {
    final auth = newAuth();
    await auth.init();
    expect((await auth.requestOtp(email: 'Asha@Example.com', purpose: 'signup', name: 'Asha')).success, true);
    final r = await auth.completeOtp(email: 'asha@example.com', code: '123456', purpose: 'signup', name: 'Asha',
        password: 'longpassword', state: 'Assam');
    expect(r.success, true, reason: r.message);
    return auth;
  }

  test('remote mode never checks whether an account exists (no enumeration)', () {
    final auth = newAuth();
    expect(auth.isRemote, true);
    expect(auth.canCheckAccounts, false);
  });

  test('sign-up with the emailed code creates a session and stores only the refresh token', () async {
    final auth = await signedUp();
    expect(auth.isAuthenticated, true);
    expect(auth.currentUser!.name, 'Asha');
    expect(auth.currentUser!.phoneOrEmail, 'asha@example.com');
    expect(auth.currentUser!.state, 'Assam');
    expect(tokens.token, startsWith('ref-'));
    expect(jsonDecode(server.requests.first.body)['email'], 'asha@example.com'); // normalised before sending
    expect(await auth.accessToken(), startsWith('acc-'));
  });

  test('a wrong code is reported with the server message', () async {
    final auth = newAuth();
    await auth.init();
    await auth.requestOtp(email: 'a@b.co', purpose: 'signup');
    final r = await auth.completeOtp(email: 'a@b.co', code: '000000', purpose: 'signup', password: 'longpassword');
    expect(r.success, false);
    expect(r.message, contains('invalid or has expired'));
    expect(auth.isAuthenticated, false);
  });

  test('resend cooldown follows the server', () async {
    final auth = newAuth();
    await auth.init();
    expect(auth.resendSecondsLeft, 0);
    await auth.requestOtp(email: 'a@b.co', purpose: 'login');
    expect(auth.resendSecondsLeft, inInclusiveRange(58, 60));
  });

  test('password and code sign-in', () async {
    await signedUp();
    final a = newAuth();
    await a.init(); // restores the session from the stored refresh token
    await a.signOut();
    final bad = await a.signIn(phoneOrEmail: 'asha@example.com', password: 'wrong');
    expect(bad.success, false);
    expect(bad.message, 'Invalid credentials.');
    expect((await a.signIn(phoneOrEmail: 'asha@example.com', password: 'longpassword')).success, true);

    await a.signOut();
    await a.requestOtp(email: 'asha@example.com', purpose: 'login');
    expect((await a.completeOtp(email: 'asha@example.com', code: '123456', purpose: 'login')).success, true);
  });

  test('app restart restores the session through a token refresh (refresh tokens rotate)', () async {
    final first = await signedUp();
    final oldRefresh = tokens.token;
    final restarted = newAuth();
    await restarted.init();
    expect(restarted.isAuthenticated, true);
    expect(restarted.currentUser!.name, 'Asha');
    expect(tokens.token, isNot(oldRefresh)); // rotated
    expect(server.liveRefresh.containsKey(oldRefresh), false); // old one is dead
    expect(first.isAuthenticated, true);
  });

  test('a revoked session signs the user out on the next start', () async {
    await signedUp();
    server.liveRefresh.clear(); // e.g. "sign out everywhere" or token theft detected server-side
    final restarted = newAuth();
    await restarted.init();
    expect(restarted.isAuthenticated, false);
    expect(tokens.token, isNull);
  });

  test('starting offline keeps the cached profile and the session', () async {
    await signedUp();
    server.offline = true;
    final restarted = newAuth();
    await restarted.init();
    expect(restarted.isAuthenticated, true); // cached user shown
    expect(restarted.currentUser!.name, 'Asha');
    expect(tokens.token, isNotNull); // not thrown away just because the network is down
    expect(await restarted.accessToken(), isNull);
  });

  test('sign-out revokes the refresh token on the server', () async {
    final auth = await signedUp();
    final rt = tokens.token!;
    await auth.signOut();
    expect(auth.isAuthenticated, false);
    expect(tokens.token, isNull);
    expect(server.liveRefresh.containsKey(rt), false);
  });

  test('profile updates go to the server', () async {
    final auth = await signedUp();
    final u = await auth.updateProfile(name: 'Asha K', state: 'Kerala');
    expect(u!.name, 'Asha K');
    expect(u.state, 'Kerala');
    expect(server.users['asha@example.com']!['state'], 'Kerala');
  });

  test('account deletion removes the server account and signs out', () async {
    final auth = await signedUp();
    final r = await auth.deleteAccount();
    expect(r.success, true);
    expect(server.users, isEmpty);
    expect(auth.isAuthenticated, false);
    expect(tokens.token, isNull);
  });

  test('network failures give a friendly message', () async {
    final auth = newAuth();
    await auth.init();
    server.offline = true;
    final r = await auth.signIn(phoneOrEmail: 'a@b.co', password: 'x');
    expect(r.success, false);
    expect(r.message, contains('Could not reach the server'));
  });

  test('recommendation requests carry the access token when signed in', () async {
    final auth = await signedUp();
    final seen = <String?>[];
    final reco = RecommendationApiClient(
      baseUrl: 'http://reco.test',
      accessToken: auth.accessToken,
      client: MockClient((r) async {
        seen.add(r.headers['authorization']);
        return http.Response(jsonEncode({'recommendations': [], 'more': [], 'mode': 'rag', 'trace_id': 't'}), 200);
      }),
    );
    await reco.recommend(CitizenProfile());
    expect(seen.single, startsWith('Bearer acc-'));

    await auth.signOut();
    await reco.recommend(CitizenProfile());
    expect(seen.last, isNull); // anonymous after sign-out
  });

  test('local demo mode is unchanged when no server is configured', () async {
    final local = AuthService();
    await local.init();
    expect(local.isRemote, false);
    expect(local.canCheckAccounts, true);
    expect((await local.signIn(phoneOrEmail: 'citizen@haqdaar.gov.in', password: 'password123')).success, true);
    expect(await local.accessToken(), isNull);
  });
}
