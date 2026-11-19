import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:drowzydiary/models/chat_message.dart';
import 'package:drowzydiary/theme/palette.dart';
import 'package:drowzydiary/widgets/chat_bubble.dart';

Future<void> _pump(WidgetTester tester, ChatMessage message) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ChatBubble(message: message, palette: Palette.night)),
    ),
  );
}

void main() {
  testWidgets('crisis message with only text renders that text', (tester) async {
    await _pump(
      tester,
      const ChatMessage(
        id: '1',
        sender: MessageSender.ai,
        text: 'Please call 119 ext. 8 now.',
        isCrisis: true,
      ),
    );

    expect(find.text('Please call 119 ext. 8 now.'), findsOneWidget);
    expect(find.widgetWithIcon(TextButton, Icons.phone), findsOneWidget);
  });

  testWidgets('legacy crisis message falls back to prefix/phone/suffix', (tester) async {
    await _pump(
      tester,
      const ChatMessage(
        id: '2',
        sender: MessageSender.ai,
        isCrisis: true,
        crisisPrefix: 'Call ',
        crisisPhone: '119 ext. 8',
        crisisSuffix: ' today.',
      ),
    );

    expect(find.textContaining('119 ext. 8', findRichText: true), findsOneWidget);
  });
}
