import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_builtin_ai/flutter_edge_ai_builtin_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import 'prototype_config.dart';

bool _engineReady = false;

String? get _hfToken {
  final t = dotenv.env['HF_TOKEN']?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

Future<void> _ensureEngine() async {
  if (_engineReady) return;
  await FlutterEdgeAi.initialize(
    inferenceEngines: const [LiteRtLmEngine(), BuiltInAiEngine()],
    huggingFaceToken: _hfToken,
  );
  _engineReady = true;
}

String _bytes(int? b) {
  if (b == null) return '-';
  if (b >= 1e9) return '${(b / 1e9).toStringAsFixed(2)} GB';
  return '${(b / 1e6).toStringAsFixed(0)} MB';
}

String _rss() => 'RSS ${_bytes(ProcessInfo.currentRss)} (peak ${_bytes(ProcessInfo.maxRss)})';

class _Stats {
  _Stats(this.ttftMs, this.totalMs, this.tokens, this.tokenSource, this.memory);

  final int? ttftMs;
  final int totalMs;
  final int tokens;
  final String tokenSource;
  final String memory;

  String get line {
    final decodeMs = totalMs - (ttftMs ?? 0);
    final tps = decodeMs > 0 && tokens > 1 ? (tokens - 1) / (decodeMs / 1000) : null;
    return 'TTFT ${ttftMs ?? '-'} ms · total $totalMs ms · $tokens tok ($tokenSource) · '
        '${tps?.toStringAsFixed(1) ?? '-'} tok/s · $memory';
  }
}

class _Turn {
  _Turn(this.user);

  final String user;
  String reply = '';
  _Stats? stats;
  String? error;
}

class _JsonRun {
  _JsonRun(this.raw, this.ms, this.check);

  final String raw;
  final int ms;
  final JsonCheck check;
}

class DevAiScreen extends StatefulWidget {
  const DevAiScreen({super.key});

  @override
  State<DevAiScreen> createState() => _DevAiScreenState();
}

class _DevAiScreenState extends State<DevAiScreen> {
  ProtoModel _selected = protoModels.last;
  PreferredBackend _backend = PreferredBackend.gpu;
  final Map<String, int?> _onDisk = {};
  BuiltInAiAvailability? _builtIn;
  String? _builtInError;

  int? _progress;
  CancelToken? _cancel;
  String _status = '';
  bool _busy = false;

  InferenceModel? _model;
  InferenceChat? _chat;
  String? _loadedInfo;

  final List<_Turn> _turns = [];
  final _input = TextEditingController();
  final _chatScroll = ScrollController();
  bool _generating = false;

  final List<_JsonRun> _jsonRuns = [];
  bool _jsonRunning = false;
  bool _constrained = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _unload();
    _input.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _set(VoidCallback f) {
    if (mounted) setState(f);
  }

  Future<void> _guard(String label, Future<void> Function() body) async {
    _set(() {
      _busy = true;
      _status = '$label…';
    });
    try {
      await body();
    } catch (e) {
      _set(() => _status = '$label failed: $e');
    } finally {
      _set(() {
        _busy = false;
        _progress = null;
      });
    }
  }

  Future<void> _refresh() async {
    await _guard('Init', () async {
      await _ensureEngine();
      for (final m in protoModels.where((m) => !m.isBuiltIn)) {
        final name = m.installName!;
        int? size;
        if (await FlutterEdgeAi.isModelInstalled(name)) {
          final f = File(await FlutterEdgeAi.getModelPath(name));
          size = f.existsSync() ? f.lengthSync() : null;
        }
        _onDisk[name] = size;
      }
      try {
        _builtIn = await BuiltInAi.availability();
      } catch (e) {
        _builtInError = '$e';
      }
      _set(() => _status = 'Ready');
    });
  }

  Future<void> _download(ProtoModel m) async {
    final v = m.variant!;
    _cancel = CancelToken();
    final sw = Stopwatch()..start();
    await _guard('Download ${m.label}', () async {
      try {
        await FlutterEdgeAi.installModelFromCatalog(v, foreground: Platform.isAndroid ? true : null)
            .withProgress((p) => _set(() => _progress = p))
            .withCancelToken(_cancel!)
            .install(activate: false);
      } catch (e) {
        if (CancelToken.isCancel(e)) {
          _set(() => _status = 'Download cancelled');
          return;
        }
        rethrow;
      }
      await _refresh();
      _set(() => _status = 'Downloaded ${m.label}: ${_bytes(_onDisk[m.installName])} '
          'in ${(sw.elapsed.inSeconds / 60).toStringAsFixed(1)} min');
    });
    _cancel = null;
  }

  Future<void> _delete(ProtoModel m) async {
    await _guard('Delete ${m.label}', () async {
      if (_loadedInfo?.startsWith(m.label) == true) await _unload();
      await FlutterEdgeAi.uninstallModel(m.installName!);
      await _refresh();
    });
  }

  Future<void> _unload() async {
    final chat = _chat, model = _model;
    _chat = null;
    _model = null;
    _set(() => _loadedInfo = null);
    try {
      await chat?.close();
      await model?.close();
    } catch (_) {}
  }

  Future<void> _load() async {
    final m = _selected;
    await _guard('Load ${m.label}', () async {
      await _unload();
      final sw = Stopwatch()..start();
      final InferenceModel model;
      if (m.isBuiltIn) {
        final spec = BuiltInAiModels.forCurrentPlatform;
        if (spec == null) throw StateError('No OS model on this platform');
        await BuiltInAi.ensureReady(onProgress: (p) => _set(() => _progress = p));
        await FlutterEdgeAi.installModel(modelType: spec.modelType, fileType: ModelFileType.builtIn)
            .fromBundled(spec.name)
            .install();
        model = await FlutterEdgeAi.getActiveModel(maxTokens: 4096);
      } else {
        await FlutterEdgeAi.installModelFromCatalog(m.variant!).install();
        model = await FlutterEdgeAi.getActiveModel(
          defaults: m.variant!.runtimeDefaults,
          preferredBackend: _backend,
        );
      }
      _model = model;
      await _newChat();
      final backend = model.activeBackend?.name ?? (m.isBuiltIn ? 'os' : '?');
      _set(() {
        _loadedInfo = '${m.label} · backend $backend · load ${sw.elapsedMilliseconds} ms · ${_rss()}';
        _status = 'Loaded';
      });
    });
  }

  Future<void> _newChat() async {
    await _chat?.close();
    _chat = await _model!.openChat(systemInstruction: chatSystemPrompt, maxOutputTokens: 256);
    _set(_turns.clear);
  }

  int _engineOutputTokens() {
    try {
      return _chat!.session.getSessionMetrics().outputTokens;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final chat = _chat;
    if (text.isEmpty || chat == null || _generating) return;
    _input.clear();
    final turn = _Turn(text);
    _set(() {
      _turns.add(turn);
      _generating = true;
    });
    final before = _engineOutputTokens();
    var chunks = 0;
    int? ttft;
    final sw = Stopwatch()..start();
    try {
      await chat.addQueryChunk(Message.text(text: text, isUser: true));
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is TextResponse && r.token.isNotEmpty) {
          ttft ??= sw.elapsedMilliseconds;
          chunks++;
          _set(() => turn.reply += r.token);
          _scrollChat();
        }
      }
    } catch (e) {
      turn.error = '$e';
    }
    final total = sw.elapsedMilliseconds;
    var tokens = _engineOutputTokens() - before;
    var source = 'engine';
    if (tokens <= 0) {
      try {
        tokens = await chat.session.sizeInTokens(turn.reply);
        source = 'tokenizer';
      } catch (_) {
        tokens = chunks;
        source = 'chunks';
      }
    }
    _set(() {
      turn.stats = _Stats(ttft, total, tokens, source, _rss());
      _generating = false;
    });
    _scrollChat();
  }

  void _scrollChat() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
    });
  }

  ResponseFormat get _jsonFormat => ResponseFormat.jsonSchema({
        'type': 'object',
        'properties': {
          'emotion': {'type': 'string', 'enum': emotions},
          'domains': {
            'type': 'array',
            'items': {'type': 'string', 'enum': domains},
          },
          'summary': {'type': 'string'},
        },
        'required': ['emotion', 'domains', 'summary'],
        'additionalProperties': false,
      });

  String? get _constrainedRefusal {
    final model = _model;
    if (model == null) return 'no model';
    if (!model.structuredOutputSupport.isSupported) return model.structuredOutputSupport.reason;
    return model.refusalFor(_jsonFormat)?.toString();
  }

  Future<void> _runJson() async {
    final model = _model;
    if (model == null || _jsonRunning || _generating) return;
    _set(() {
      _jsonRuns.clear();
      _jsonRunning = true;
    });
    for (var i = 0; i < 10 && mounted; i++) {
      final sw = Stopwatch()..start();
      String raw;
      try {
        final s = await model.openSession(
          systemInstruction: jsonSystemPrompt,
          maxOutputTokens: 200,
          responseFormat: _constrained ? _jsonFormat : null,
        );
        try {
          await s.addQueryChunk(Message.text(text: jsonUserPrompt(), isUser: true));
          raw = await s.getResponse();
        } finally {
          await s.close();
        }
      } catch (e) {
        raw = 'ERROR: $e';
      }
      final run = _JsonRun(raw, sw.elapsedMilliseconds, checkJsonOutput(raw));
      _set(() => _jsonRuns.add(run));
    }
    _set(() => _jsonRunning = false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('On-device AI prototype'),
          bottom: const TabBar(tabs: [Tab(text: 'Model'), Tab(text: 'Chat'), Tab(text: 'JSON test')]),
        ),
        body: Column(
          children: [
            if (_busy || _progress != null) LinearProgressIndicator(value: _progress == null ? null : _progress! / 100),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: Text(
                [if (_progress != null) '$_progress%', _status, if (_loadedInfo != null) '\n$_loadedInfo'].join(' '),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: TabBarView(children: [_modelTab(), _chatTab(), _jsonTab()])),
          ],
        ),
      ),
    );
  }

  Widget _modelTab() {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Text('HF_TOKEN in .env: ${_hfToken == null ? 'not set (gated models will fail)' : 'set'}',
            style: const TextStyle(fontSize: 12)),
        for (final m in protoModels) _modelTile(m),
        const SizedBox(height: 8),
        if (!_selected.isBuiltIn)
          SegmentedButton<PreferredBackend>(
            segments: const [
              ButtonSegment(value: PreferredBackend.gpu, label: Text('GPU')),
              ButtonSegment(value: PreferredBackend.cpu, label: Text('CPU')),
            ],
            selected: {_backend},
            onSelectionChanged: (s) => setState(() => _backend = s.first),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy || !_canLoad(_selected) ? null : _load,
          child: Text('Load ${_selected.label}'),
        ),
        if (_cancel != null) TextButton(onPressed: () => _cancel?.cancel(), child: const Text('Cancel download')),
      ],
    );
  }

  bool _canLoad(ProtoModel m) {
    if (m.isBuiltIn) {
      return _builtIn == BuiltInAiAvailability.available ||
          _builtIn == BuiltInAiAvailability.downloadable ||
          _builtIn == BuiltInAiAvailability.downloading;
    }
    return _onDisk[m.installName] != null;
  }

  Widget _modelTile(ProtoModel m) {
    final selected = identical(m, _selected);
    final String subtitle;
    Widget? trailing;
    if (m.isBuiltIn) {
      final name = Platform.isIOS ? 'Apple Foundation Models (iOS 26+)' : 'Gemini Nano (AICore)';
      final state = _builtInError ?? _builtIn?.name ?? 'checking…';
      subtitle = '$name\nStatus: $state${_canLoad(m) ? '' : ' — UNAVAILABLE on this device'}';
    } else {
      final f = m.file!;
      final disk = _onDisk[f.installFilename];
      subtitle = '${f.installFilename}\nexpected ${_bytes(f.sizeBytes)} · '
          '${disk == null ? 'not downloaded' : 'on disk ${_bytes(disk)}'}'
          '${f.gated ? ' · gated (HF token + license)' : ''}';
      trailing = disk == null
          ? IconButton(icon: const Icon(Icons.download), onPressed: _busy ? null : () => _download(m))
          : IconButton(icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : () => _delete(m));
    }
    return ListTile(
      dense: true,
      selected: selected,
      leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
      title: Text(m.label),
      subtitle: Text(subtitle),
      isThreeLine: true,
      trailing: trailing,
      onTap: () => setState(() => _selected = m),
    );
  }

  Widget _chatTab() {
    if (_chat == null) return const Center(child: Text('Load a model first'));
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _chatScroll,
            padding: const EdgeInsets.all(12),
            children: [
              for (final t in _turns) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(t.user, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text(t.reply.isEmpty && t.stats == null ? '…' : t.reply),
                if (t.error != null) Text(t.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                if (t.stats != null)
                  Text(t.stats!.line, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const Divider(),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'New chat',
                icon: const Icon(Icons.refresh),
                onPressed: _generating ? null : _newChat,
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  decoration: const InputDecoration(hintText: 'Tulis pesan…'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              _generating
                  ? IconButton(icon: const Icon(Icons.stop), onPressed: () => _chat?.stopGeneration())
                  : IconButton(icon: const Icon(Icons.send), onPressed: _send),
            ],
          ),
        ),
      ],
    );
  }

  Widget _jsonTab() {
    if (_model == null) return const Center(child: Text('Load a model first'));
    final refusal = _constrainedRefusal;
    final n = _jsonRuns.length;
    int count(bool Function(JsonCheck c) f) => _jsonRuns.where((r) => f(r.check)).length;
    final avgMs = n == 0 ? 0 : _jsonRuns.map((r) => r.ms).reduce((a, b) => a + b) ~/ n;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Sample: "$jsonSampleMessage"', style: TextStyle(fontSize: 12)),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Constrained decoding (responseFormat)'),
          subtitle: Text(refusal == null ? 'Supported by this model' : 'Unavailable: $refusal'),
          value: _constrained && refusal == null,
          onChanged: refusal != null || _jsonRunning ? null : (v) => setState(() => _constrained = v),
        ),
        FilledButton(
          onPressed: _jsonRunning || _generating ? null : _runJson,
          child: Text(_jsonRunning ? 'Running ${n + 1}/10…' : 'Run JSON test ×10'),
        ),
        const SizedBox(height: 12),
        if (n > 0)
          Text(
            'Valid JSON (strict): ${count((c) => c.strict)}/$n\n'
            'Valid JSON (after stripping extra text): ${count((c) => c.lenient)}/$n\n'
            'Matches schema: ${count((c) => c.schema)}/$n\n'
            'Avg time: $avgMs ms · ${_rss()}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        for (final (i, r) in _jsonRuns.indexed)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('#${i + 1} ${r.check.strict ? 'strict OK' : r.check.lenient ? 'lenient OK' : 'FAIL'}'
                '${r.check.lenient && !r.check.schema ? ' (${r.check.error})' : ''} · ${r.ms} ms'),
            children: [SelectableText(r.raw, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))],
          ),
      ],
    );
  }
}
