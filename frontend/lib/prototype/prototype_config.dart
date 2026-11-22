import 'dart:convert';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

class ProtoModel {
  const ProtoModel(this.label, this.variant);

  final String label;
  final InferenceVariant? variant;

  bool get isBuiltIn => variant == null;
  ModelArtifact? get file => variant?.file;
  String? get installName => file?.installFilename;
}

final List<ProtoModel> protoModels = [
  ProtoModel('Gemma 4 E2B', LiteRtLmModels.gemma4E2bIt.generic),
  ProtoModel('Gemma 3n E2B', LiteRtLmModels.gemma3nE2bIt.generic),
  ProtoModel('Gemma 3 1B', LiteRtLmModels.gemma3_1bIt.q4Ekv4096),
  ProtoModel('Qwen3 0.6B', LiteRtLmModels.qwen3_0_6b.dynamicInt4),
  const ProtoModel('OS built-in', null),
];

const String chatSystemPrompt =
    'Kamu adalah teman check-in tidur PillowTalk yang hangat dan tidak menghakimi. '
    'Jawab dalam bahasa Indonesia yang alami dan singkat, cukup 1 sampai 3 kalimat. '
    'Kamu bukan terapis atau dokter: jangan mendiagnosis dan jangan memberi nasihat medis. '
    'Jangan bilang sesuatu pasti menyebabkan masalah tidur; sebut saja sebagai kemungkinan. '
    'Ajukan paling banyak satu pertanyaan yang lembut.';

const String jsonSystemPrompt =
    'Kamu menganalisis pesan check-in tidur. Balas HANYA dengan satu objek JSON yang valid, '
    'tanpa teks lain dan tanpa markdown.';

const String jsonSampleMessage =
    'Aku capek banget hari ini, bos marah-marah soal deadline. '
    'Tadi sore minum kopi dua gelas dan sekarang susah tidur.';

const List<String> emotions = ['joy', 'sadness', 'anger', 'fear', 'surprise', 'love', 'neutral'];
const List<String> domains = ['relationship', 'sleep', 'work', 'health', 'sleep_substances'];

String jsonUserPrompt() => 'Analisis pesan berikut dan kembalikan objek JSON dengan tepat tiga kunci:\n'
    '"emotion": salah satu dari ${emotions.join(", ")}\n'
    '"domains": daftar berisi nol atau lebih dari ${domains.join(", ")}\n'
    '"summary": satu kalimat ringkasan dalam bahasa Indonesia\n\n'
    'Pesan: "$jsonSampleMessage"';

class JsonCheck {
  const JsonCheck({required this.strict, required this.lenient, required this.schema, this.error});

  final bool strict;
  final bool lenient;
  final bool schema;
  final String? error;
}

JsonCheck checkJsonOutput(String raw) {
  Object? decoded;
  var strict = false;
  try {
    decoded = jsonDecode(raw.trim());
    strict = true;
  } catch (_) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        decoded = jsonDecode(raw.substring(start, end + 1));
      } catch (_) {}
    }
  }
  if (decoded == null) {
    return const JsonCheck(strict: false, lenient: false, schema: false, error: 'not JSON');
  }
  final error = _schemaError(decoded);
  return JsonCheck(strict: strict, lenient: true, schema: error == null, error: error);
}

String? _schemaError(Object? v) {
  if (v is! Map<String, dynamic>) return 'not an object';
  if (!emotions.contains(v['emotion'])) return 'bad emotion';
  final d = v['domains'];
  if (d is! List || d.any((e) => !domains.contains(e))) return 'bad domains';
  final s = v['summary'];
  if (s is! String || s.trim().isEmpty) return 'bad summary';
  return null;
}
