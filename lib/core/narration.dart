import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plays a chapter's narration and follows along paragraph by paragraph. Saved books play from the phone,
/// others stream from the library server. Playback carries on with the screen off.
class Narration extends ChangeNotifier {
  Narration() {
    _subscriptions.addAll([
      _player.playerStateStream.listen((state) {
        final loading = state.processingState == ProcessingState.loading || state.processingState == ProcessingState.buffering;
        if (state.processingState == ProcessingState.completed && playing) {
          if (repeat != null) {
            unawaited(_loopBack());
          } else {
            unawaited(_player.pause());
            unawaited(_player.seek(Duration.zero));
          }
        }
        if (state.playing != playing || loading != this.loading) {
          playing = state.playing;
          this.loading = loading;
          if (!playing) {
            unawaited(_remember());
          }
          notifyListeners();
        }
      }),
      _player.positionStream.listen((value) {
        position.value = value;
        _follow(value);
        final stretch = repeat;
        if (stretch != null && stretch.endMs > 0 && value.inMilliseconds >= stretch.endMs && !_looping) {
          unawaited(_loopBack());
        }
      }),
      _player.durationStream.listen((value) {
        duration.value = value ?? Duration.zero;
      }),
    ]);
  }

  static const speeds = [0.75, 1.0, 1.25, 1.5];

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);

  Map<String, dynamic>? chapter;
  Map<String, dynamic>? track;
  String bookTitle = '';
  String? paragraphId;
  bool playing = false;
  bool loading = false;
  bool failed = false;
  double speed = 1;
  Map<String, dynamic>? lastListened;

  /// Asks to show notifications. Android 13 and newer hide the player controls in the notification bar and on the
  /// lock screen until the listener allows it, so this runs once, the first time anything plays.
  Future<bool> Function()? askToNotify;
  List<(int, String)> _cues = const [];

  /// A stretch of paragraphs played again and again while memorising. [left] is how many more times, or -1
  /// to repeat until stopped. [endMs] of 0 means the end of the recording.
  ({int startMs, int endMs, int from, int to, int left})? repeat;
  bool _looping = false;

  bool isCurrent(String? chapterId) => chapterId != null && chapter?['id'] == chapterId;

  /// The Quran reciter the listener picked, by name. Null plays the first one recorded.
  String? reciter;

  /// The reciters recorded for a chapter, in the order the server lists them.
  static List<String> reciters(Map<String, dynamic> chapter) => [
        for (final row in (chapter['audio'] as List? ?? const []))
          if ((row as Map)['language'] == 'ar' && (row['narrator'] ?? '').toString().isNotEmpty) row['narrator'].toString(),
      ];

  /// The narration to play: the reader's language when recorded, otherwise the Arabic recitation, otherwise any.
  /// Among Arabic recitations the chosen [reciter] wins when this chapter has one by them.
  static Map<String, dynamic>? pickTrack(Map<String, dynamic> chapter, String language, {String? reciter}) {
    final tracks = [for (final row in (chapter['audio'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
    if (tracks.isEmpty) {
      return null;
    }
    Map<String, dynamic>? arabic() => tracks.where((t) => t['language'] == 'ar' && t['narrator'] == reciter).firstOrNull ?? tracks.where((t) => t['language'] == 'ar').firstOrNull;
    if (language == 'ar') {
      return arabic() ?? tracks.first;
    }
    return tracks.where((t) => t['language'] == language).firstOrNull ?? arabic() ?? tracks.first;
  }

  Future<void> loadLast() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('last_listened');
    lastListened = saved == null ? null : Map<String, dynamic>.from(jsonDecode(saved) as Map);
    reciter = prefs.getString('reciter');
    notifyListeners();
  }

  /// Switches the Quran reciter. A recitation already playing carries on with the new voice from the same ayah.
  Future<void> setReciter(String name, {required String language}) async {
    reciter = name;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString('reciter', name);
    final current = chapter;
    if (current == null || track?['language'] != 'ar' || track?['narrator'] == name) {
      return;
    }
    final ayah = paragraphId;
    await start(current, bookTitle: bookTitle, language: language);
    if (ayah != null && canRepeat(ayah)) {
      await seekParagraph(ayah);
    }
  }

  Future<void> start(Map<String, dynamic> data, {required String bookTitle, required String language, Duration? from}) async {
    final picked = pickTrack(data, language, reciter: reciter);
    if (picked == null) {
      return;
    }
    chapter = data;
    track = picked;
    this.bookTitle = bookTitle;
    paragraphId = null;
    repeat = null;
    failed = false;
    loading = true;
    _cues = [
      for (final cue in (picked['cues'] as List? ?? const []))
        if ((cue as Map)['paragraph'] != null) ((cue['start_ms'] as num).toInt(), cue['paragraph'].toString()),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    notifyListeners();
    unawaited(_askToNotifyOnce());
    final tag = MediaItem(
      id: '${data['id']}-${picked['language']}-${picked['narrator'] ?? ''}',
      title: (data['title'] ?? '').toString(),
      album: bookTitle,
      artist: (picked['narrator'] ?? '').toString(),
    );
    final file = (picked['file'] ?? '').toString();
    final source = file.isNotEmpty && File(file).existsSync() ? AudioSource.file(file, tag: tag) : AudioSource.uri(Uri.parse((picked['url'] ?? '').toString()), tag: tag);
    try {
      await _player.setAudioSource(source, initialPosition: from);
      await _player.setSpeed(speed);
      unawaited(_player.play());
    } on Object {
      failed = true;
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _askToNotifyOnce() async {
    final ask = askToNotify;
    if (ask == null || !Platform.isAndroid) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('asked_notify_playback') ?? false) {
      return;
    }
    await prefs.setBool('asked_notify_playback', true);
    await ask();
  }

  Future<void> toggle() => playing ? _player.pause() : _player.play();

  Future<void> skip(int seconds) {
    final target = position.value + Duration(seconds: seconds);
    final end = duration.value;
    return _player.seek(target < Duration.zero ? Duration.zero : (end > Duration.zero && target > end ? end : target));
  }

  Future<void> seek(Duration value) => _player.seek(value);

  /// Jumps the narration to where a paragraph starts, when it has a cue.
  Future<void> seekParagraph(String id) async {
    final cue = _cues.where((c) => c.$2 == id).firstOrNull;
    if (cue != null) {
      // Choosing another paragraph ends any repeating.
      if (repeat != null) {
        stopRepeat();
      }
      await _player.seek(Duration(milliseconds: cue.$1));
      if (!playing) {
        await _player.play();
      }
    }
  }

  /// True when the recording marks where this paragraph starts, so it can be repeated on its own.
  bool canRepeat(String id) => _cues.any((c) => c.$2 == id);

  /// Repeats from the start of [fromId] to the end of [toId], [times] times, or until stopped when -1.
  /// [from] and [to] are the paragraph numbers shown to the reader.
  Future<void> repeatRange({required String fromId, required String toId, required int from, required int to, required int times}) async {
    final start = _cues.where((c) => c.$2 == fromId).firstOrNull;
    final last = _cues.lastIndexWhere((c) => c.$2 == toId);
    if (start == null || last < 0) {
      return;
    }
    final endMs = last + 1 < _cues.length ? _cues[last + 1].$1 : 0;
    repeat = (startMs: start.$1, endMs: endMs, from: from, to: to, left: times < 0 ? -1 : times - 1);
    notifyListeners();
    await _player.seek(Duration(milliseconds: start.$1));
    if (!playing) {
      await _player.play();
    }
  }

  void stopRepeat() {
    repeat = null;
    notifyListeners();
  }

  /// Back to the start of the stretch, or a pause at its end once the last time has played.
  Future<void> _loopBack() async {
    final stretch = repeat;
    if (stretch == null) {
      return;
    }
    _looping = true;
    try {
      if (stretch.left == 0) {
        repeat = null;
        notifyListeners();
        await _player.pause();
        return;
      }
      repeat = (startMs: stretch.startMs, endMs: stretch.endMs, from: stretch.from, to: stretch.to, left: stretch.left < 0 ? -1 : stretch.left - 1);
      notifyListeners();
      await _player.seek(Duration(milliseconds: stretch.startMs));
      if (!_player.playing) {
        await _player.play();
      }
    } finally {
      _looping = false;
    }
  }

  Future<void> nextSpeed() async {
    speed = speeds[(speeds.indexOf(speed) + 1) % speeds.length];
    notifyListeners();
    await _player.setSpeed(speed);
  }

  Future<void> stop() async {
    await _remember();
    await _player.stop();
    chapter = null;
    track = null;
    paragraphId = null;
    repeat = null;
    notifyListeners();
  }

  void _follow(Duration value) {
    if (_cues.isEmpty) {
      return;
    }
    final ms = value.inMilliseconds;
    String? current;
    for (final (start, id) in _cues) {
      if (start > ms) {
        break;
      }
      current = id;
    }
    if (current != paragraphId) {
      paragraphId = current;
      notifyListeners();
      unawaited(_remember());
    }
  }

  Future<void> _remember() async {
    final data = chapter;
    if (data == null) {
      return;
    }
    lastListened = {
      'chapter': data['id'],
      'chapter_title': data['title'] ?? '',
      'book_title': bookTitle,
      'position_ms': position.value.inMilliseconds,
    };
    await (await SharedPreferences.getInstance()).setString('last_listened', jsonEncode(lastListened));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}
