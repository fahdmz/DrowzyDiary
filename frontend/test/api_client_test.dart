import 'package:drowzydiary/services/api_client.dart';
import 'package:drowzydiary/services/auth_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAuth extends Fake implements AuthService {
  FakeAuth({this.refreshWorks = true});

  final bool refreshWorks;
  String token = 'old';
  int refreshes = 0;
  int expirations = 0;

  @override
  String? get accessToken => token;

  @override
  Future<bool> refreshSession() async {
    refreshes++;
    if (refreshWorks) token = 'new';
    return refreshWorks;
  }

  @override
  Future<void> expireSession() async => expirations++;
}

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8000'));

  test('a request that outlives the timeout throws ApiTimeoutException', () async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return http.Response('{}', 200);
    });
    final api = ApiClient(FakeAuth(),
        client: client, timeout: const Duration(milliseconds: 20));

    expect(api.get('/profile'), throwsA(isA<ApiTimeoutException>()));
  });

  test('401 refreshes the session once and retries with the new token', () async {
    final auth = FakeAuth();
    final seen = <String?>[];
    final client = MockClient((req) async {
      seen.add(req.headers['Authorization']);
      return req.headers['Authorization'] == 'Bearer new'
          ? http.Response('{"ok": true}', 200)
          : http.Response('expired', 401);
    });

    final json = await ApiClient(auth, client: client).get('/profile');

    expect(json, {'ok': true});
    expect(seen, ['Bearer old', 'Bearer new']);
    expect(auth.refreshes, 1);
    expect(auth.expirations, 0);
  });

  test('401 after a failed refresh ends the session and throws', () async {
    final auth = FakeAuth(refreshWorks: false);
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('expired', 401);
    });

    await expectLater(
      ApiClient(auth, client: client).get('/profile'),
      throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', true)),
    );

    expect(calls, 1);
    expect(auth.expirations, 1);
  });

  test('401 that persists after a refresh retries only once, then ends the session', () async {
    final auth = FakeAuth();
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('expired', 401);
    });

    await expectLater(
        ApiClient(auth, client: client).post('/chat/message', body: {'a': 1}),
        throwsA(isA<ApiException>()));

    expect(calls, 2);
    expect(auth.refreshes, 1);
    expect(auth.expirations, 1);
  });

  test('429 and 503 surface as ApiException with matching flags and no refresh', () async {
    final auth = FakeAuth();
    for (final entry in {429: 'isRateLimited', 503: 'isUnavailable'}.entries) {
      final client = MockClient((_) async =>
          http.Response('x', entry.key, headers: {'retry-after': '2'}));
      final error = await ApiClient(auth, client: client)
          .post('/chat/s/end')
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<ApiException>());
      final api = error as ApiException;
      expect(entry.value == 'isRateLimited' ? api.isRateLimited : api.isUnavailable, isTrue);
    }
    expect(auth.refreshes, 0);
  });
}
