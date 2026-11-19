enum MessageSender { ai, user }

/// A single chat turn. Crisis messages carry their full copy in [text]; legacy
/// rows instead split it into prefix/phone/suffix so the UI can render the
/// phone number as a tappable `tel:` link.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    this.text,
    this.isCrisis = false,
    this.crisisPrefix,
    this.crisisPhone,
    this.crisisSuffix,
  });

  final Object id;
  final MessageSender sender;
  final String? text;
  final bool isCrisis;
  final String? crisisPrefix;
  final String? crisisPhone;
  final String? crisisSuffix;
}
