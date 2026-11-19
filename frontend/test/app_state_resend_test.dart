import 'dart:async';

import 'package:drowzydiary/models/chat_message.dart';
import 'package:drowzydiary/services/api_client.dart';
import 'package:drowzydiary/services/auth_service.dart';
import 'package:drowzydiary/services/chat_service.dart';
import 'package:drowzydiary/services/profile_service.dart';
import 'package:drowzydiary/services/recap_service.dart';
import 'package:drowzydiary/services/stt_service.dart';
import 'package:drowzydiary/services/tts_service.dart';
import 'package:drowzydiary/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

class FakeAuth extends Fake implements AuthService {
  @override
  bool get isSignedIn => false;

  @override
  Stream<AuthState> get onAuthStateChange => const Stream.empty();
}

class FakeProfile extends Fake implements ProfileService {}

class FakeRecaps extends Fake implements RecapService {}

class FakeTts extends Fake implements TtsService {}

class FakeStt extends Fake implements SttService {}

class FakeChat extends Fake implements ChatService {
  final results = <Object>[];

  @override
  Future<StartedSession> startSession(
          {required String checkinMode, required String language}) async =>
      StartedSession(sessionId: 's1', sessionStatus: 'active', messages: [
        const ChatMessage(id: 'g', sender: MessageSender.ai, text: 'hi'),
      ]);

  @override
  Future<SendMessageResult> sendMessage(
      {required String sessionId,
      required String text,
      required String language}) async {
    final next = results.removeAt(0);
    if (next is Exception) throw next;
    return next as SendMessageResult;
  }
}

SendMessageResult reply() => SendMessageResult(
      userMessage: const ChatMessage(id: 'u', sender: MessageSender.user),
      aiMessage:
          const ChatMessage(id: 'a', sender: MessageSender.ai, text: 'ok'),
      sessionCompleted: false,
    );

void main() {
  late FakeChat chat;
  late AppState app;

  setUp(() async {
    chat = FakeChat();
    app = AppState(
      authService: FakeAuth(),
      chatService: chat,
      recapService: FakeRecaps(),
      profileService: FakeProfile(),
      ttsService: FakeTts(),
      sttService: FakeStt(),
    );
    await app.selectCheckin(CheckinMode.night);
  });

  int bubbles(String text) => app.messages
      .where((m) => m.sender == MessageSender.user && m.text == text)
      .length;

  test('resending after a failure reuses the user bubble and drops the error', () async {
    chat.results.addAll([ApiException(500, 'x'), reply()]);

    await app.sendMessage('hello');
    expect(bubbles('hello'), 1);
    expect(app.messages.last.sender, MessageSender.ai);
    final failedLength = app.messages.length;

    await app.sendMessage('hello');

    expect(bubbles('hello'), 1);
    expect(app.messages.length, failedLength);
    expect(app.messages.last.text, 'ok');
  });

  test('a different message after a failure gets its own bubble', () async {
    chat.results.addAll([ApiException(500, 'x'), reply()]);

    await app.sendMessage('hello');
    await app.sendMessage('something else');

    expect(bubbles('hello'), 1);
    expect(bubbles('something else'), 1);
  });

  test('the same text after a confirmed send is a new bubble', () async {
    chat.results.addAll([reply(), reply()]);

    await app.sendMessage('hello');
    await app.sendMessage('hello');

    expect(bubbles('hello'), 2);
  });

  test('after a rate-limit rejection the resend adds the bubble back once', () async {
    chat.results.addAll([ApiException(429, 'x'), reply()]);

    await app.sendMessage('hello');
    expect(bubbles('hello'), 0);
    expect(app.draft, 'hello');

    await app.sendMessage('hello');
    expect(bubbles('hello'), 1);
  });
}
