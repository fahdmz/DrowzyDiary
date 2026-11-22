import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dev_ai_screen.dart';

class PrototypeLauncher extends StatelessWidget {
  const PrototypeLauncher({super.key});

  static bool get enabled =>
      kDebugMode &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      bottom: MediaQuery.paddingOf(context).bottom + 96,
      child: Opacity(
        opacity: 0.6,
        child: FloatingActionButton.small(
          heroTag: 'dev-ai-prototype',
          tooltip: 'On-device AI prototype (debug only)',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DevAiScreen())),
          child: const Icon(Icons.memory),
        ),
      ),
    );
  }
}
