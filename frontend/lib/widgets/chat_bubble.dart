import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../theme/palette.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message, required this.palette});

  final ChatMessage message;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == MessageSender.user;
    final bg = message.isCrisis
        ? Palette.crisisBubble
        : (isUser ? palette.userBubble : palette.card);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
          child: message.isCrisis ? _crisisText() : _plainText(),
        ),
      ),
    );
  }

  Widget _plainText() {
    return Text(
      message.text ?? '',
      style: TextStyle(fontSize: 14.5, height: 1.55, color: palette.text),
    );
  }

  Widget _crisisText() {
    final text = message.text;
    final hasText = text != null && text.trim().isNotEmpty;
    final style = TextStyle(fontSize: 14.5, height: 1.55, color: palette.text);
    if (!hasText) {
      return RichText(
        text: TextSpan(
          style: style,
          children: [
            TextSpan(text: message.crisisPrefix ?? ''),
            TextSpan(
              text: message.crisisPhone ?? '',
              style: const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
              recognizer: TapGestureRecognizer()..onTap = _callCrisisLine,
            ),
            TextSpan(text: message.crisisSuffix ?? ''),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: style),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _callCrisisLine,
          icon: const Icon(Icons.phone, size: 18),
          label: const Text('119'),
        ),
      ],
    );
  }

  static Future<void> _callCrisisLine() => launchUrl(Uri.parse('tel:119'));
}
