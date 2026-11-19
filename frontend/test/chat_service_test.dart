import 'dart:convert';

import 'package:drowzydiary/services/api_client.dart';
import 'package:drowzydiary/services/chat_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'api_client_test.dart' show FakeAuth;

http.Response turn(String text) => http.Response(
    jsonEncode({
      'user_message': {'id': 'u', 'sender': 'user', 'text': text},
      'ai_message': {'id': 'a', 'sender': 'ai', 'text': 'ok'},
      'session_status': 'active',
    }),
    200);

void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8000'));

  late List<String?> keys;
  late List<int> statuses;

  ChatService serviceReturning({FakeAuth? auth}) {
    final client = MockClient((req) async {
      keys.add(req.headers['Idempotency-Key']);
      final status = statuses.removeAt(0);
      if (status != 200) return http.Response('err', status);
      return turn((jsonDecode(req.body) as Map)['text'] as String);
    });
    return ChatService(ApiClient(auth ?? FakeAuth(), client: client));
  }

  setUp(() {
    keys = [];
    statuses = [];
  });

  Future<void> send(ChatService s, String text, {String session = 's1'}) =>
      s.sendMessage(sessionId: session, text: text, language: 'en').then(
          (_) {}, onError: (_) {});

  test('resending a message that failed reuses its Idempotency-Key', () async {
    statuses = [500, 200];
    final service = serviceReturning();

    await send(service, 'hello');
    await send(service, 'hello');

    expect(keys, hasLength(2));
    expect(keys[0], isNotNull);
    expect(keys[0]!.length, inInclusiveRange(8, 128));
    expect(keys[1], keys[0]);
  });

  test('a new message gets a new key', () async {
    statuses = [500, 200, 200];
    final service = serviceReturning();

    await send(service, 'hello');
    await send(service, 'something else');
    // Same text again after it was confirmed is a new message, not a resend.
    await send(service, 'something else');

    expect(keys.toSet(), hasLength(3));
  });

  test('the same text in a different session gets a new key', () async {
    statuses = [500, 200];
    final service = serviceReturning();

    await send(service, 'hello', session: 's1');
    await send(service, 'hello', session: 's2');

    expect(keys[1], isNot(keys[0]));
  });

  test('the 401-refresh retry inside ApiClient reuses the same key', () async {
    statuses = [401, 200];
    final auth = FakeAuth();
    final service = serviceReturning(auth: auth);

    await send(service, 'hello');

    expect(auth.refreshes, 1);
    expect(keys, hasLength(2));
    expect(keys[1], keys[0]);
  });

  test('/chat/message uses the longer timeout, other calls keep the default', () async {
    final client = MockClient((req) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return req.url.path == '/chat/message' ? turn('hi') : http.Response('{}', 200);
    });
    final api = ApiClient(FakeAuth(),
        client: client, timeout: const Duration(milliseconds: 20));

    await expectLater(api.get('/profile'), throwsA(isA<ApiTimeoutException>()));
    final result = await ChatService(api)
        .sendMessage(sessionId: 's1', text: 'hi', language: 'en');
    expect(result.aiMessage.text, 'ok');
  });

  test('send timeout covers the backend worst case (2 calls x 30s x 3 attempts)', () {
    expect(ChatService.sendMessageTimeout,
        greaterThan(const Duration(seconds: 2 * 30 * 3)));
  });

  group('409 in progress', () {
    late List<Duration> waits;

    ChatService serviceWith(List<http.Response> responses) {
      waits = [];
      final client = MockClient((req) async {
        keys.add(req.headers['Idempotency-Key']);
        return responses.removeAt(0);
      });
      return ChatService(ApiClient(FakeAuth(), client: client),
          delay: (d) async => waits.add(d));
    }

    http.Response conflict([String? retryAfter]) => http.Response('busy', 409,
        headers: {if (retryAfter != null) 'retry-after': retryAfter});

    Future<SendMessageResult> send409(ChatService s) =>
        s.sendMessage(sessionId: 's1', text: 'hello', language: 'en');

    test('waits Retry-After, then retries once with the same key', () async {
      final service = serviceWith([conflict('3'), turn('hello')]);

      final result = await send409(service);

      expect(result.aiMessage.text, 'ok');
      expect(waits, [const Duration(seconds: 3)]);
      expect(keys, hasLength(2));
      expect(keys[1], keys[0]);
    });

    test('defaults to 2s without a header and caps at 5s', () async {
      await send409(serviceWith([conflict(), turn('hello')]));
      expect(waits, [const Duration(seconds: 2)]);

      await send409(serviceWith([conflict('30'), turn('hello')]));
      expect(waits, [const Duration(seconds: 5)]);
    });

    test('a second 409 is surfaced after exactly one retry', () async {
      final service = serviceWith([conflict('1'), conflict('1'), turn('hello')]);

      await expectLater(
          send409(service),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
      expect(keys, hasLength(2));
    });

    test('other errors are not retried', () async {
      final service = serviceWith([http.Response('boom', 500), turn('hello')]);

      await expectLater(send409(service), throwsA(isA<ApiException>()));
      expect(keys, hasLength(1));
      expect(waits, isEmpty);
    });
  });
}
