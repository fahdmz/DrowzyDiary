import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthChangeEvent, AuthException, AuthState;

import '../data/date_format.dart';
import '../data/strings.dart';
import '../models/chat_message.dart';
import '../models/language.dart';
import '../models/recap_entry.dart';
import '../models/sleep_factor.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/profile_service.dart';
import '../services/recap_service.dart';
import '../theme/palette.dart';

enum AppScreen { auth, home, chat }

enum AuthMode { login, signup }

enum HomeTab { recap, checkin, profile }

enum CheckinMode { night, morning }

enum RecapFilter { all, night, morning }

const _connectionErrorText =
    "Sorry, I'm having trouble connecting right now. Please try again.";

/// A recap entry plus the group date-label it belongs to, resolved once a
/// user opens it — mirrors the design's `selectedEntryObj`.
class OpenRecapEntry {
  OpenRecapEntry({required this.entry, required this.dateLabelKey});

  final RecapEntry entry;
  final String dateLabelKey;
}

/// Single source of truth for the whole app. Screen/UI state lives here
/// directly; anything that needs the network goes through the services
/// (auth/chat/recap/profile) injected below rather than talking to
/// Supabase or http directly — see services/api_client.dart.
class AppState extends ChangeNotifier {
  AppState({
    AuthService? authService,
    ApiClient? apiClient,
    ChatService? chatService,
    RecapService? recapService,
    ProfileService? profileService,
  })  : _authService = authService ?? AuthService.instance(),
        _chatService = chatService ??
            ChatService(
                apiClient ?? ApiClient(authService ?? AuthService.instance())),
        _recapService = recapService ??
            RecapService(
                apiClient ?? ApiClient(authService ?? AuthService.instance())),
        _profileService = profileService ??
            ProfileService(
                apiClient ?? ApiClient(authService ?? AuthService.instance())) {
    _bootstrap();
    // Google OAuth completes via an external browser + deep-link redirect,
    // not a value we can await directly — this is what actually moves us
    // to Home once that redirect lands and Supabase picks up the session.
    _authSub = _authService.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && screen == AppScreen.auth) {
        goHome();
      } else if (data.event == AuthChangeEvent.signedOut &&
          !_signingOut &&
          screen != AppScreen.auth) {
        // ApiClient ended the session after a 401 it couldn't recover from.
        _resetToAuth();
        _showBanner(message: t.noticeSessionExpired);
      }
    });
  }

  final AuthService _authService;
  final ChatService _chatService;
  final RecapService _recapService;
  final ProfileService _profileService;
  StreamSubscription<AuthState>? _authSub;
  bool _signingOut = false;

  AppScreen screen = AppScreen.auth;
  AuthMode authMode = AuthMode.login;
  HomeTab activeTab = HomeTab.checkin;
  CheckinMode? checkinMode;

  bool isAuthLoading = false;
  bool isGoogleLoading = false;
  String? authError;

  final List<ChatMessage> messages = [];
  String draft = '';
  bool aiTyping = false;
  // Bubble (and its trailing error notice) of a send that failed; resending
  // the same text reuses it, matching ChatService reusing the idempotency key.
  ChatMessage? _unconfirmedBubble;
  ChatMessage? _unconfirmedError;
  String? _currentSessionId;
  bool checkinCompleted = false;

  bool bedtimeMode = false;
  String quietHoursStart = '22:00';
  String quietHoursEnd = '07:00';

  List<RecapGroup> recapData = [];
  bool recapsLoaded = false;
  RecapFilter recapFilter = RecapFilter.all;
  DateTime? selectedMonth;
  String? selectedEntryId;
  bool showDeleteConfirm = false;

  /// Which reminder the "preview night/morning reminder" links in the
  /// Check-in tab are currently showing in [NotificationBanner].
  CheckinMode? notifPreviewType;
  bool notifOpen = false;

  /// Non-null while the banner is showing an error/status notice rather than
  /// a check-in reminder.
  String? notifMessage;
  Timer? _notifTimer;

  String? expandedFactorKey;
  List<SleepFactor> sleepFactors = [];
  List<double> weeklySleepHours = List.filled(7, 0.0);
  String? avgSleepTimeDisplay;
  String? avgWakeTimeDisplay;

  int age = 29;
  bool isEditingAge = false;
  String ageDraft = '29';
  String? fullName;

  AppLanguage lang = AppLanguage.id;

  UiStrings get t => uiStringsFor(lang);
  Palette get palette =>
      checkinMode == CheckinMode.morning ? Palette.morning : Palette.night;

  // --- bootstrap / auth ---------------------------------------------------

  /// Supabase sessions persist ~30 days, so on a fresh launch we may already
  /// be signed in — skip straight to Home in that case instead of showing
  /// the auth screen.
  Future<void> _bootstrap() async {
    if (_authService.isSignedIn) {
      screen = AppScreen.home;
      notifyListeners();
      await _loadHomeData();
    }
  }

  void setAuthMode(AuthMode mode) {
    authMode = mode;
    authError = null;
    notifyListeners();
  }

  Future<void> logIn({required String email, required String password}) async {
    authError = null;
    isAuthLoading = true;
    notifyListeners();
    try {
      await _authService.signIn(email: email, password: password);
      await goHome();
    } on AuthException catch (e) {
      authError = e.message;
    } catch (e) {
      debugPrint('Auth failed: $e');
      authError = 'Something went wrong. Please try again.';
    } finally {
      isAuthLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    authError = null;
    isAuthLoading = true;
    notifyListeners();
    try {
      await _authService.signUp(
          email: email, password: password, fullName: fullName);
      await goHome();
    } on AuthException catch (e) {
      authError = e.message;
    } catch (e) {
      debugPrint('Auth failed: $e');
      authError = 'Something went wrong. Please try again.';
    } finally {
      isAuthLoading = false;
      notifyListeners();
    }
  }

  /// Launches the Google OAuth flow. This returns as soon as the external
  /// browser opens — it does NOT mean the user is signed in yet. The actual
  /// navigation to Home happens in the `onAuthStateChange` listener set up
  /// in the constructor, once the OAuth redirect lands back in the app.
  Future<void> signInWithGoogle() async {
    authError = null;
    isGoogleLoading = true;
    notifyListeners();
    try {
      await _authService.signInWithGoogle();
    } on AuthException catch (e) {
      authError = e.message;
    } catch (e) {
      debugPrint('Auth failed: $e');
      authError = 'Something went wrong. Please try again.';
    } finally {
      isGoogleLoading = false;
      notifyListeners();
    }
  }

  // --- navigation ---------------------------------------------------------

  Future<void> goHome() async {
    screen = AppScreen.home;
    notifyListeners();
    await _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    await Future.wait([
      loadProfile(),
      loadRecaps(),
      loadWeeklySleep(),
      loadSleepFactors(),
    ]);
  }

  void setTab(HomeTab tab) {
    screen = AppScreen.home;
    activeTab = tab;
    notifyListeners();
  }

  Future<void> selectCheckin(CheckinMode mode) async {
    screen = AppScreen.chat;
    checkinMode = mode;
    checkinCompleted = false;
    messages.clear();
    _currentSessionId = null;
    notifyListeners();

    final sessionId = await _ensureSession();
    if (sessionId == null) {
      messages.add(const ChatMessage(
        id: 'session-start-failed',
        sender: MessageSender.ai,
        text: _connectionErrorText,
      ));
    }
    notifyListeners();
  }

  /// Starts a chat session if one isn't already active. Used both when
  /// first entering the chat and as a retry path from [sendMessage], so a
  /// failed [selectCheckin] doesn't leave the input row permanently dead.
  ///
  /// The backend resumes today's in-progress session for this check-in type
  /// if one exists (or hands back today's already-completed one, read-only,
  /// enforcing one check-in of each type per day) — either way it returns
  /// the full message history, which replaces whatever's currently loaded.
  Future<String?> _ensureSession() async {
    if (_currentSessionId != null) return _currentSessionId;
    final mode = checkinMode;
    if (mode == null) return null;
    try {
      final started = await _chatService.startSession(
          checkinMode: mode.name, language: lang.name);
      _currentSessionId = started.sessionId;
      checkinCompleted = started.sessionStatus == 'completed';
      messages
        ..clear()
        ..addAll(started.messages);
      return started.sessionId;
    } catch (e) {
      _reportError(e, t.noticeConnection, 'Starting chat session failed');
      return null;
    }
  }

  /// Leaving chat is just navigation now, not an end-of-session action — an
  /// in-progress check-in stays active server-side so reopening the same
  /// type later today resumes it instead of starting over. It only gets
  /// finalized (recap generated) once a new day rolls it over in
  /// `_ensureSession`, or `session_status` comes back completed on its own.
  Future<void> exitChat() async {
    screen = AppScreen.home;
    activeTab = HomeTab.checkin;
    aiTyping = false;
    notifyListeners();
    await loadRecaps();
  }

  Future<void> logOut() async {
    _signingOut = true;
    try {
      await _authService.signOut();
    } catch (e) {
      debugPrint('Sign-out failed, resetting locally anyway: $e');
    } finally {
      _signingOut = false;
    }
    _resetToAuth();
  }

  void _resetToAuth() {
    screen = AppScreen.auth;
    authMode = AuthMode.login;
    activeTab = HomeTab.checkin;
    recapData = [];
    recapsLoaded = false;
    sleepFactors = [];
    weeklySleepHours = List.filled(7, 0.0);
    messages.clear();
    notifyListeners();
  }

  // --- chat -----------------------------------------------------------------

  void updateDraft(String value) {
    draft = value;
    notifyListeners();
  }

  Future<void> sendMessage([String? overrideText]) async {
    final text = (overrideText ?? draft).trim();
    // Today's already-completed check-ins render read-only (see ChatScreen,
    // which hides the input row entirely for these) — no input reaches here.
    if (text.isEmpty || checkinCompleted) return;

    final sessionId = await _ensureSession();
    if (sessionId == null) {
      messages.add(ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch,
        sender: MessageSender.ai,
        text: _connectionErrorText,
      ));
      notifyListeners();
      return;
    }

    final previous = _unconfirmedBubble;
    if (previous != null && previous.text == text && messages.contains(previous)) {
      messages.remove(_unconfirmedError);
    } else {
      _unconfirmedBubble = ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch,
          sender: MessageSender.user,
          text: text);
      messages.add(_unconfirmedBubble!);
    }
    _unconfirmedError = null;
    draft = '';
    aiTyping = true;
    notifyListeners();

    try {
      final result = await _chatService.sendMessage(
          sessionId: sessionId, text: text, language: lang.name);
      _unconfirmedBubble = null;
      messages.add(result.aiMessage);
      _refreshStatsAfterChatTurn(sessionCompleted: result.sessionCompleted);
      if (result.sessionCompleted) checkinCompleted = true;
    } catch (e) {
      debugPrint('Sending message failed: $e');
      if (e is ApiException && e.isRateLimited) {
        // Rejected before anything was saved: hand the text back to retry.
        messages.remove(_unconfirmedBubble);
        _unconfirmedBubble = null;
        draft = text;
        _showBanner(message: t.noticeRateLimited);
      } else {
        _unconfirmedError = ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch,
          sender: MessageSender.ai,
          text: _connectionErrorText,
        );
        messages.add(_unconfirmedError!);
      }
    } finally {
      aiTyping = false;
      notifyListeners();
    }
  }

  void _refreshStatsAfterChatTurn({required bool sessionCompleted}) {
    unawaited(Future.wait([
      loadWeeklySleep(),
      loadSleepFactors(),
      if (sessionCompleted) loadRecaps(),
    ]));
  }

  // --- recap ------------------------------------------------------------

  Future<void> loadRecaps() async {
    try {
      final items = await _recapService.listRecaps();
      final groups = <RecapGroup>[];
      DateTime? lastDay;
      for (final item in items) {
        final day = DateTime(item.date.year, item.date.month, item.date.day);
        final entry = RecapEntry(
          id: item.id,
          date: item.date,
          time: item.time,
          isNight: item.isNight,
          preview: item.preview ?? '',
          title: item.title,
          summary: item.summary,
        );
        if (lastDay == day && groups.isNotEmpty) {
          groups.last.items.add(entry);
        } else {
          groups.add(RecapGroup(
              dateLabelKey: recapDateLabelKey(day),
              dateValue: day,
              items: [entry]));
          lastDay = day;
        }
      }
      recapData = groups;
      recapsLoaded = true;
      notifyListeners();
    } catch (e) {
      // keep whatever was last loaded rather than wiping the screen
      if (recapsLoaded) {
        debugPrint('Refreshing recaps failed: $e');
      } else {
        _reportError(e, t.noticeConnection, 'Loading recaps failed');
      }
    }
  }

  void setRecapFilter(RecapFilter filter) {
    recapFilter = filter;
    notifyListeners();
  }

  void updateSelectedMonth(DateTime? month) {
    selectedMonth = month;
    notifyListeners();
  }

  void clearSelectedMonth() {
    selectedMonth = null;
    notifyListeners();
  }

  void openRecapEntry(String id) {
    selectedEntryId = id;
    notifyListeners();
    _loadRecapTranscript(id);
  }

  Future<void> _loadRecapTranscript(String id) async {
    try {
      final detail = await _recapService.getRecap(id);
      for (final group in recapData) {
        for (final item in group.items) {
          if (item.id == id) item.transcript = detail.transcript;
        }
      }
      notifyListeners();
    } catch (e) {
      _reportError(e, t.noticeConnection, 'Loading recap transcript failed');
    }
  }

  void closeRecapDetail() {
    selectedEntryId = null;
    notifyListeners();
  }

  void requestDeleteEntry() {
    showDeleteConfirm = true;
    notifyListeners();
  }

  void cancelDeleteEntry() {
    showDeleteConfirm = false;
    notifyListeners();
  }

  Future<void> deleteEntry() async {
    final id = selectedEntryId;
    if (id == null) return;
    for (final group in recapData) {
      group.items.removeWhere((it) => it.id == id);
    }
    recapData.removeWhere((group) => group.items.isEmpty);
    selectedEntryId = null;
    showDeleteConfirm = false;
    notifyListeners();

    try {
      await _recapService.deleteRecap(id);
    } catch (e) {
      // The entry still exists server-side, so say so and put it back.
      _reportError(e, t.noticeDeleteFailed, 'Deleting recap failed');
      await loadRecaps();
    }
  }

  List<RecapGroup> get filteredRecapGroups {
    return recapData
        .where((g) =>
            selectedMonth == null ||
            (g.dateValue.year == selectedMonth!.year &&
                g.dateValue.month == selectedMonth!.month))
        .map((g) {
          final items = g.items.where((it) {
            switch (recapFilter) {
              case RecapFilter.all:
                return true;
              case RecapFilter.night:
                return it.isNight;
              case RecapFilter.morning:
                return !it.isNight;
            }
          }).toList();
          return RecapGroup(
              dateLabelKey: g.dateLabelKey,
              dateValue: g.dateValue,
              items: items);
        })
        .where((g) => g.items.isNotEmpty)
        .toList();
  }

  String recapGroupLabel(RecapGroup group) {
    final base =
        dateLabelTranslations[lang]![group.dateLabelKey] ?? group.dateLabelKey;
    if (isWeekdayLabelKey(group.dateLabelKey)) {
      return '$base · ${formatShortDate(group.dateValue, lang)}';
    }
    return base;
  }

  String recapItemTimeDisplay(RecapGroup group, RecapEntry entry) {
    if (group.dateLabelKey == 'Last week') {
      return '${formatShortDate(group.dateValue, lang)} · ${entry.time}';
    }
    return entry.time;
  }

  String get monthFilterLabel =>
      selectedMonth != null ? formatMonthYear(selectedMonth!, lang) : t.month;

  OpenRecapEntry? get openEntry {
    if (selectedEntryId == null) return null;
    for (final group in recapData) {
      for (final item in group.items) {
        if (item.id == selectedEntryId) {
          return OpenRecapEntry(entry: item, dateLabelKey: group.dateLabelKey);
        }
      }
    }
    return null;
  }

  // --- notification preview ------------------------------------------------

  void previewNightNotif() => _showBanner(type: CheckinMode.night);
  void previewMorningNotif() => _showBanner(type: CheckinMode.morning);

  /// Shows the banner with either a check-in reminder ([type]) or a plain
  /// notice ([message]) — errors reuse the reminder banner's slide-in/timeout.
  void _showBanner({CheckinMode? type, String? message}) {
    _notifTimer?.cancel();
    notifPreviewType = type;
    notifMessage = message;
    notifOpen = true;
    notifyListeners();
    _notifTimer = Timer(const Duration(seconds: 6), () {
      notifOpen = false;
      notifyListeners();
    });
  }

  /// Logs the error for debug builds and shows the user a short notice —
  /// the specific one for rate limits, busy/unavailable, timeouts and expired
  /// sessions, otherwise [fallback].
  void _reportError(Object error, String fallback, String context) {
    debugPrint('$context: $error');
    _showBanner(message: _noticeFor(error, fallback));
  }

  String _noticeFor(Object error, String fallback) {
    if (error is ApiTimeoutException) return t.noticeTimeout;
    if (error is ApiException) {
      if (error.isRateLimited) return t.noticeRateLimited;
      if (error.isUnavailable) return t.noticeBusy;
      if (error.isUnauthorized) return t.noticeSessionExpired;
    }
    return fallback;
  }

  void dismissNotifBanner() {
    _notifTimer?.cancel();
    notifOpen = false;
    notifyListeners();
  }

  /// Tapping the banner itself, like tapping a real push notification, deep
  /// links straight into that check-in's chat.
  Future<void> openNotifBanner() async {
    if (notifMessage != null) return dismissNotifBanner();
    final type = notifPreviewType;
    _notifTimer?.cancel();
    notifOpen = false;
    notifyListeners();
    if (type != null) await selectCheckin(type);
  }

  // --- profile ------------------------------------------------------------

  Future<void> loadProfile() async {
    try {
      final profile = await _profileService.getProfile();
      age = profile.age ?? age;
      ageDraft = '$age';
      lang = profile.language == 'id' ? AppLanguage.id : AppLanguage.en;
      bedtimeMode = profile.bedtimeMode;
      quietHoursStart = profile.quietHoursStart;
      quietHoursEnd = profile.quietHoursEnd;
      fullName = profile.fullName;
      notifyListeners();
    } catch (e) {
      debugPrint('Loading profile failed, keeping local defaults: $e');
    }
  }

  Future<void> loadWeeklySleep() async {
    try {
      final stats = await _profileService.getWeeklySleep();
      const order = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final hours = List<double>.filled(7, 0.0);
      for (final point in stats.week) {
        final index = order.indexOf(point.day);
        if (index != -1) hours[index] = point.hours;
      }
      weeklySleepHours = hours;
      avgSleepTimeDisplay = stats.avgSleepTime;
      avgWakeTimeDisplay = stats.avgWakeTime;
      notifyListeners();
    } catch (e) {
      debugPrint('Loading weekly sleep failed: $e');
    }
  }

  Future<void> loadSleepFactors() async {
    try {
      final factors = await _profileService.getSleepFactors();
      sleepFactors = factors
          .map((f) => SleepFactor(
                nameKey: f.nameKey,
                level: f.level,
                occurrences: f.occurrences
                    .map((o) => SleepOccurrence(
                          checkinLabelKey: o.checkinLabelKey,
                          time: formatOccurrenceTime(o.time),
                        ))
                    .toList(),
              ))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Loading sleep factors failed: $e');
    }
  }

  void toggleFactor(String nameKey) {
    expandedFactorKey = expandedFactorKey == nameKey ? null : nameKey;
    notifyListeners();
  }

  /// "10:00 PM – 7:00 AM" style label built from the 24h "HH:MM" values the
  /// backend stores.
  String get quietHoursDisplay =>
      '${_format12Hour(quietHoursStart)} – ${_format12Hour(quietHoursEnd)}';

  Future<void> updateQuietHours(String start, String end) async {
    quietHoursStart = start;
    quietHoursEnd = end;
    notifyListeners();
    try {
      await _profileService.updateProfile(
          quietHoursStart: start, quietHoursEnd: end);
    } catch (e) {
      _reportError(e, t.noticeSettingsFailed, 'Saving quiet hours failed');
    }
  }

  Future<void> toggleBedtime() async {
    bedtimeMode = !bedtimeMode;
    notifyListeners();
    try {
      await _profileService.updateProfile(bedtimeMode: bedtimeMode);
    } catch (e) {
      _reportError(e, t.noticeSettingsFailed, 'Saving bedtime mode failed');
    }
  }

  void startEditAge() {
    isEditingAge = true;
    ageDraft = '$age';
    notifyListeners();
  }

  void updateAgeDraft(String value) {
    ageDraft = value;
    notifyListeners();
  }

  Future<void> saveAge() async {
    final parsed = int.tryParse(ageDraft);
    if (parsed != null && parsed > 0) age = parsed;
    isEditingAge = false;
    notifyListeners();
    try {
      await _profileService.updateProfile(age: age);
    } catch (e) {
      _reportError(e, t.noticeSettingsFailed, 'Saving age failed');
    }
  }

  Future<void> setLang(AppLanguage value) async {
    lang = value;
    notifyListeners();
    try {
      await _profileService.updateProfile(language: value.name);
    } catch (e) {
      _reportError(e, t.noticeSettingsFailed, 'Saving language failed');
    }
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}

/// "22:00" -> "10:00 PM", "07:00" -> "7:00 AM".
String _format12Hour(String hhmm) {
  final parts = hhmm.split(':');
  final hour24 = int.tryParse(parts[0]) ?? 0;
  final minute = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
  final period = hour24 < 12 ? 'AM' : 'PM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:$minute $period';
}
