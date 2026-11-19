import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime config, loaded from `.env` at startup (see `main.dart`) so no
/// secrets live in source. Copy `.env.example` to `.env` and fill it in —
/// `.env` itself is gitignored.
class Env {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  /// sb_publishable_ key; falls back to the legacy SUPABASE_ANON_KEY name.
  static String get supabasePublishableKey {
    final key = dotenv.env['SUPABASE_PUBLISHABLE_KEY'];
    if (key != null && key.isNotEmpty) return key;
    return dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  }
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000';
}
