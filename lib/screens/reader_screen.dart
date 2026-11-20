import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/layout.dart';
import '../core/narration.dart';
import '../core/prefs.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ask_scholar.dart';
import '../widgets/player_bar.dart';
import '../widgets/share_card.dart';
import '../widgets/ui.dart';

/// Colours for each page colour the reader can pick.
class ReaderLook {
  const ReaderLook({required this.page, required this.ink, required this.body, required this.muted, required this.card});

  final Color page;
  final Color ink;
  final Color body;
  final Color muted;
  final Color card;

  static const _light = ReaderLook(page: Color(0xFFF7F7F5), ink: Color(0xFF0B0B0C), body: Color(0xFF3C3C38), muted: Color(0xFF6E6E68), card: Colors.white);
  static const _sepia = ReaderLook(page: Color(0xFFF4ECD8), ink: Color(0xFF3B2F1E), body: Color(0xFF5B4A33), muted: Color(0xFF8A7A60), card: Color(0xFFFBF5E6));
  static const _night = ReaderLook(page: Color(0xFF121412), ink: Color(0xFFE8E6DF), body: Color(0xFFC9C6BC), muted: Color(0xFF8E8C85), card: Color(0xFF1E211F));

  /// In the app's dark look a light page reads as the night page, so the reader never flashes white.
  static ReaderLook of(ReaderTheme theme) => switch (theme) {
        ReaderTheme.light => Palette.dark ? _night : _light,
        ReaderTheme.sepia => _sepia,
        ReaderTheme.night => _night,
      };
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.chapterId, required this.bookTitle, this.author = '', this.total = 0, this.startAt});

  final String chapterId;
  final String bookTitle;
  final String author;
  final int total;

  /// The paragraph number to open at, such as an ayah picked from Go to.
  final int? startAt;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  Map<String, dynamic>? _chapter;

  /// The chapter's paragraphs, read once when it loads rather than on every redraw.
  List<Map<String, dynamic>> _paragraphs = const [];
  Object? _error;
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {};
  String? _followed;

  /// The paragraph tapped while nothing plays here, which shows its actions.
  String? _picked;
  late final narration = AppScope.read(context).narration;

  bool _finished = false;
  Timer? _placeSoon;

  /// Saves the first paragraph on screen a moment after scrolling stops, so Continue reading opens there.
  void _watchPlace() {
    _placeSoon?.cancel();
    _placeSoon = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _chapter == null) {
        return;
      }
      for (final paragraph in _paragraphs) {
        final box = _keys[paragraph['id'].toString()]?.currentContext?.findRenderObject();
        if (box is RenderBox && box.attached && box.localToGlobal(Offset.zero).dy + box.size.height > 120) {
          final services = AppScope.read(context);
          final number = (paragraph['number'] as num).toInt();
          unawaited(services.prefs.rememberPlace(widget.chapterId, number));
          final bookId = (_chapter!['book'] as Map?)?['id']?.toString();
          if (bookId != null) {
            unawaited(services.readingLog.reached(bookId, widget.chapterId, number));
          }
          return;
        }
      }
    });
  }

  /// Counts the chapter as read once the reader reaches its end, with a small finish moment for a long one.
  void _watchEnd() {
    if (_finished || !_scroll.hasClients || _chapter == null) {
      return;
    }
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 24) {
      _markRead(celebrateIt: position.maxScrollExtent > 600);
    }
  }

  Timer? _shortRead;

  /// A chapter short enough to fit on the screen has no end to scroll to, so a short stay counts as reading it.
  void _watchShort() {
    _shortRead?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _scroll.position.maxScrollExtent < 24) {
        _shortRead = Timer(const Duration(seconds: 8), () {
          if (mounted) {
            _markRead(celebrateIt: false);
          }
        });
      }
    });
  }

  void _markRead({required bool celebrateIt}) {
    if (_finished) {
      return;
    }
    _finished = true;
    final services = AppScope.read(context);
    final chapterId = _chapter!['id'].toString();
    final bookId = (_chapter!['book'] as Map?)?['id']?.toString();
    if (bookId != null) {
      unawaited(services.readingLog.finished(bookId, chapterId, _paragraphs.length));
    }
    if (celebrateIt) {
      HapticFeedback.mediumImpact();
      unawaited(celebrate(context, context.t('chapter_done'), body: context.t('chapter_done_body')));
      unawaited(services.reminders.chapterFinished(chapterId, (_chapter!['title'] ?? '').toString(), services.prefs.language));
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll
      ..addListener(_watchEnd)
      ..addListener(_watchPlace);
    unawaited(_load());
    WidgetsBinding.instance.addPostFrameCallback((_) => narration.addListener(_follow));
  }

  @override
  void dispose() {
    narration.removeListener(_follow);
    _placeSoon?.cancel();
    _shortRead?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the paragraph being read on screen while this chapter's narration plays.
  void _follow() {
    final id = narration.paragraphId;
    if (!mounted || id == null || id == _followed || !narration.isCurrent(widget.chapterId)) {
      return;
    }
    _followed = id;
    _scrollTo(id);
  }

  void _scrollTo(String id) {
    final target = _keys[id]?.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, alignment: 0.25, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      return;
    }
    // Paragraphs far off screen are not built yet: jump close by, then settle on it.
    final paragraphs = (_chapter?['paragraphs'] as List? ?? const []);
    final index = paragraphs.indexWhere((p) => (p as Map)['id'] == id);
    if (index < 0 || !_scroll.hasClients) {
      return;
    }
    _scroll.jumpTo(_scroll.position.maxScrollExtent * index / paragraphs.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settled = _keys[id]?.currentContext;
      if (settled != null) {
        Scrollable.ensureVisible(settled, alignment: 0.25);
      }
    });
  }

  void _take(Map<String, dynamic> data) {
    _chapter = data;
    _paragraphs = [for (final row in (data['paragraphs'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final services = AppScope.read(context);
    try {
      // A copy kept on the phone opens at once; newer text, such as a fresh translation, replaces it quietly.
      final data = await services.chapter(widget.chapterId, onUpdate: (fresh) {
        if (mounted) {
          setState(() => _take(fresh));
        }
      });
      if (!mounted) {
        return;
      }
      setState(() => _take(data));
      final at = widget.startAt;
      if (at != null) {
        final match = (data['paragraphs'] as List? ?? const []).where((p) => (p as Map)['number'] == at).firstOrNull;
        if (match != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo((match as Map)['id'].toString()));
        }
      }
      final book = Map<String, dynamic>.from(data['book'] as Map);
      unawaited(services.prefs.remember(book: book['id'].toString(), bookTitle: book['title'].toString(), chapter: data['id'].toString(), chapterTitle: (data['title'] ?? '').toString()));
      unawaited(services.readingLog
          .opened(
            bookId: book['id'].toString(),
            bookTitle: book['title'].toString(),
            quran: book['quran'] == true,
            chapterId: data['id'].toString(),
            chapterTitle: (data['title'] ?? '').toString(),
            total: widget.total,
          )
          .then((_) => services.reminders.readingMoved(services.prefs.language)));
      _watchShort();
      if (services.session.signedIn) {
        // Reading progress follows the reader to other devices. A failed save is retried on the next chapter.
        unawaited(services.api
            .put('progress/${book['id']}', body: {'chapter': data['id'], 'language': services.prefs.translation ?? 'ar'}, auth: true)
            .then<void>((_) {}, onError: (Object _) {}));
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  /// Bookmarks the paragraph being narrated, or else the first paragraph showing at the top of the screen.
  Future<void> _bookmark() async {
    final services = AppScope.read(context);
    if (!services.session.signedIn) {
      showMessage(context, context.t('sign_in_bookmark'));
      return;
    }
    final paragraphs = (_chapter?['paragraphs'] as List? ?? const []);
    String? target = narration.isCurrent(widget.chapterId) ? narration.paragraphId : null;
    if (target == null) {
      for (final paragraph in paragraphs) {
        final id = (paragraph as Map)['id'].toString();
        final box = _keys[id]?.currentContext?.findRenderObject();
        if (box is RenderBox && box.attached && box.localToGlobal(Offset.zero).dy + box.size.height > 120) {
          target = id;
          break;
        }
      }
    }
    target ??= paragraphs.isEmpty ? null : (paragraphs.first as Map)['id'].toString();
    if (target == null) {
      return;
    }
    try {
      await services.api.post('bookmarks', body: {'paragraph': target}, auth: true);
      if (mounted) {
        showMessage(context, context.t('bookmarked'));
      }
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  /// Shares a paragraph as an image card, with the Arabic and the translation the reader is using.
  Future<void> _share(Map<String, dynamic> paragraph) {
    final chapter = _chapter ?? const {};
    final quran = (chapter['book'] as Map?)?['quran'] == true;
    final reference = quran
        ? '${chapter['title'] ?? ''} ${chapter['number']}:${paragraph['number']}'
        : '${widget.bookTitle}, ${chapter['title'] ?? ''}';
    final language = AppScope.read(context).prefs.translation;
    final translation = language == null ? '' : ((paragraph['translations'] as Map?)?[language] ?? '').toString();
    return sharePassage(
      context,
      arabic: (paragraph['arabic'] ?? '').toString(),
      translation: translation,
      reference: reference,
      link: chapterLink(chapter['id'].toString(), paragraph: paragraph['number']),
    );
  }

  /// Repeats the paragraph being narrated, or a stretch starting from it, for memorising.
  Future<void> _repeatFrom(int index) async {
    final paragraphs = _paragraphs;
    final first = paragraphs[index];
    if (!narration.canRepeat(first['id'].toString())) {
      showMessage(context, context.t('repeat_unavailable'));
      return;
    }
    final choice = await showModalBottomSheet<(int, int)>(
      context: context,
      backgroundColor: Palette.surface,
      showDragHandle: true,
      builder: (_) => _RepeatSheet(from: (first['number'] as num).toInt(), last: (paragraphs.last['number'] as num).toInt()),
    );
    if (choice == null || !mounted) {
      return;
    }
    final end = paragraphs.where((p) => p['number'] == choice.$1).firstOrNull ?? first;
    await narration.repeatRange(
      fromId: first['id'].toString(),
      toId: end['id'].toString(),
      from: (first['number'] as num).toInt(),
      to: (end['number'] as num).toInt(),
      times: choice.$2,
    );
  }

  void _open(String? chapterId) {
    if (chapterId == null) {
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(chapterId: chapterId, bookTitle: widget.bookTitle, author: widget.author, total: widget.total),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    final chapter = _chapter;
    final paragraphs = _paragraphs;
    final translation = prefs.translation;
    final mode = translation == null ? ReadingMode.arabic : prefs.mode;
    final languageName = translation == null ? '' : context.t('lang_$translation');
    final translatedCount = paragraphs.where((p) => ((p['translations'] as Map?)?[translation] ?? '').toString().isNotEmpty).length;
    final number = chapter?['number'];
    final position = number == null ? '' : (widget.total > 0 ? context.t('chapter_of', {'n': number, 'total': widget.total}) : context.t('chapter_n', {'n': number}));
    final padding = Layout.page(context);
    final narration = AppScope.of(context).narration;
    final playingHere = narration.isCurrent(widget.chapterId);
    final hasAudio = (chapter?['audio'] as List? ?? const []).isNotEmpty;
    final look = ReaderLook.of(prefs.theme);
    final base = Theme.of(context);
    final scaffold = Scaffold(
      backgroundColor: look.page,
      bottomNavigationBar: chapter != null && hasAudio
          ? SafeArea(
              minimum: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding.left, 6, padding.right, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (playingHere && narration.repeat != null) _Repeating(narration: narration),
                    if (Narration.reciters(chapter).length > 1) _ReciterChoice(chapter: chapter),
                    PlayerBar(chapter: chapter, bookTitle: widget.bookTitle),
                  ],
                ),
              ),
            )
          : null,
      body: _Page(
        theme: prefs.theme,
        child: SafeArea(
          child: SelectionArea(
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: padding.copyWith(top: 8),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          RoundButton(icon: Icons.arrow_back_rounded, label: context.t('back'), onTap: () => Navigator.of(context).maybePop()),
                          Expanded(child: Text(position, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: look.muted))),
                          RoundButton(icon: Icons.bookmark_border_rounded, label: context.t('bookmark'), onTap: _bookmark),
                          const SizedBox(width: 6),
                          Semantics(
                            button: true,
                            label: context.t('text_size'),
                            excludeSemantics: true,
                            child: Material(
                              color: Palette.surface,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: prefs.nextSize,
                                child: SizedBox(width: 36, height: 36, child: Center(child: Text('Aa', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.ink)))),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          RoundButton(
                            icon: switch (prefs.theme) {
                              ReaderTheme.light => Icons.light_mode_outlined,
                              ReaderTheme.sepia => Icons.wb_twilight_outlined,
                              ReaderTheme.night => Icons.dark_mode_outlined,
                            },
                            label: context.t('page_colour'),
                            onTap: () async {
                              await prefs.nextTheme();
                              if (context.mounted) {
                                showMessage(context, context.t('theme_${prefs.theme.name}'));
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DisplayTitle(widget.bookTitle, second: (chapter?['title'] ?? '').toString(), size: 30),
                            if (widget.author.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(widget.author, style: Theme.of(context).textTheme.bodySmall),
                            ],
                            if ((chapter?['arabic_title'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              SizedBox(width: double.infinity, child: ArabicText(chapter!['arabic_title'].toString(), size: 20, color: look.body)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Segmented<String>(
                        height: 34,
                        options: [('ar', context.t('mode_arabic')), ('sw', context.t('lang_sw')), ('en', context.t('lang_en'))],
                        value: mode == ReadingMode.arabic ? 'ar' : translation!,
                        onChanged: prefs.setReadingLanguage,
                      ),
                      if (mode != ReadingMode.arabic) ...[
                        const SizedBox(height: 8),
                        Segmented<ReadingMode>(
                          height: 34,
                          options: [
                            (ReadingMode.both, context.t('mode_both', {'lang': languageName})),
                            (ReadingMode.translation, context.t('mode_only', {'lang': languageName})),
                          ],
                          value: mode,
                          onChanged: prefs.setMode,
                        ),
                      ],
                      if (chapter != null && mode != ReadingMode.arabic && translatedCount < paragraphs.length)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                          child: Text(
                            context.t(translatedCount == 0 ? 'review_all' : 'review_part', {'lang': languageName}),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (chapter != null && mode != ReadingMode.arabic && translatedCount > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(Icons.info_outline_rounded, size: 15, color: look.muted),
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(context.t('translation_note'), style: Theme.of(context).textTheme.bodySmall)),
                            ],
                          ),
                        ),
                      if (chapter != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                          child: Row(
                            children: [
                              Icon(Icons.forum_outlined, size: 15, color: look.muted),
                              const SizedBox(width: 6),
                              Flexible(child: Text(context.t('hard_to_follow'), style: Theme.of(context).textTheme.bodySmall)),
                              TextButton(
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                                onPressed: () => askScholar(
                                  context,
                                  reference: (chapter['book'] as Map?)?['quran'] == true ? (chapter['title'] ?? '').toString() : '${widget.bookTitle}, ${chapter['title'] ?? ''}',
                                  link: chapterLink(chapter['id'].toString()),
                                ),
                                child: Text(context.t('ask_scholar'), style: TextStyle(fontSize: 12.5, color: Palette.green, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      if (chapter == null) LoadView(error: _error, onRetry: _load, skeleton: SkeletonText(color: look.card)),
                    ],
                  ),
                ),
                if (chapter != null)
                  SliverPadding(
                    padding: padding,
                    sliver: SliverList.builder(
                      itemCount: paragraphs.length,
                      itemBuilder: (context, index) {
                        final id = paragraphs[index]['id'].toString();
                        return _Paragraph(
                          key: _keys.putIfAbsent(id, GlobalKey.new),
                          paragraph: paragraphs[index],
                          translation: translation,
                          mode: mode,
                          scale: prefs.textScale,
                          look: look,
                          playing: playingHere && narration.paragraphId == id,
                          onTap: playingHere ? () => narration.seekParagraph(id) : () => setState(() => _picked = _picked == id ? null : id),
                          picked: !playingHere && _picked == id,
                          onShare: () => _share(paragraphs[index]),
                          onRepeat: playingHere && narration.repeat == null ? () => _repeatFrom(index) : null,
                        );
                      },
                    ),
                  ),
                if (chapter != null)
                  SliverPadding(
                    padding: padding.copyWith(top: 18, bottom: 28),
                    sliver: SliverToBoxAdapter(
                      child: PairRow(
                        first: BusyButton(label: context.t('previous_chapter'), style: BusyStyle.light, onPressed: chapter['previous'] == null ? null : () async => _open(chapter['previous'] as String?)),
                        second: BusyButton(label: context.t('next_chapter'), onPressed: chapter['next'] == null ? null : () async => _open(chapter['next'] as String?)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: prefs.theme == ReaderTheme.night ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Theme(data: base.copyWith(textTheme: base.textTheme.apply(bodyColor: look.body, displayColor: look.ink)), child: scaffold),
    );
  }
}

/// The patterned page in light mode, a plain page in sepia and night.
class _Page extends StatelessWidget {
  const _Page({required this.theme, required this.child});

  final ReaderTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return theme == ReaderTheme.light ? PatternBackground(child: child) : ColoredBox(color: ReaderLook.of(theme).page, child: child);
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({super.key, required this.paragraph, required this.translation, required this.mode, required this.scale, required this.look, required this.onShare, this.playing = false, this.picked = false, this.onTap, this.onRepeat});

  final Map<String, dynamic> paragraph;
  final String? translation;
  final bool playing;
  final VoidCallback? onTap;
  final VoidCallback? onRepeat;
  final VoidCallback onShare;
  final bool picked;
  final ReadingMode mode;
  final double scale;
  final ReaderLook look;

  @override
  Widget build(BuildContext context) {
    final text = translation == null ? '' : ((paragraph['translations'] as Map?)?[translation] ?? '').toString();
    final showArabic = mode != ReadingMode.translation || text.isEmpty;
    final showTranslation = mode != ReadingMode.arabic && text.isNotEmpty;
    // The paragraph being narrated sits on a white card, as in the design.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: playing || picked ? look.card : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: playing ? const [BoxShadow(color: Color(0x0F0B0B0C), blurRadius: 22, offset: Offset(0, 8))] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (playing)
              Row(
                children: [
                  Tag(context.t('now_playing')),
                  const Spacer(),
                  _Action(icon: Icons.ios_share_rounded, label: context.t('share'), onTap: onShare),
                  if (onRepeat != null)
                    TextButton.icon(
                      onPressed: onRepeat,
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Palette.green),
                      icon: const Icon(Icons.repeat_rounded, size: 16),
                      label: Text(context.t('repeat'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            // Switching language or layout cross-fades the words and eases the height, so the page never jumps.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                child: Column(
                  key: ValueKey('${translation ?? 'ar'}/${mode.name}/${text.isEmpty}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showArabic) ArabicText((paragraph['arabic'] ?? '').toString(), size: 25 * scale, height: 1.85, color: look.ink, number: (paragraph['number'] as num?)?.toInt()),
                    if (showArabic && showTranslation) const SizedBox(height: 4),
                    if (showTranslation)
                      Text(
                        text,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.justify,
                        style: TextStyle(fontSize: 14.5 * scale, height: 1.6, color: mode == ReadingMode.translation || playing ? look.ink : look.body),
                      ),
                  ],
                ),
              ),
            ),
            if (picked)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _Action(icon: Icons.ios_share_rounded, label: context.t('share_image'), onTap: onShare),
              ),
          ],
        ),
      ),
    );
  }
}

/// Which reciter plays the Quran, with a sheet to pick another. Shown when a surah has more than one.
class _ReciterChoice extends StatelessWidget {
  const _ReciterChoice({required this.chapter});

  final Map<String, dynamic> chapter;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final narration = services.narration;
    final names = Narration.reciters(chapter);
    final current = names.contains(narration.reciter) ? narration.reciter! : names.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ActionChip(
          avatar: Icon(Icons.record_voice_over_outlined, size: 16, color: Palette.green),
          label: Text(context.t('reciter_name', {'name': current}), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          onPressed: () async {
            final picked = await showModalBottomSheet<String>(
              context: context,
              backgroundColor: Palette.surface,
              showDragHandle: true,
              builder: (sheet) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(context.t('choose_reciter'), style: Theme.of(context).textTheme.titleSmall)),
                    for (final name in names)
                      ListTile(
                        title: Text(name, style: const TextStyle(fontSize: 14)),
                        trailing: name == current ? Icon(Icons.check_rounded, color: Palette.green) : null,
                        onTap: () => Navigator.of(sheet).pop(name),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
            if (picked != null && picked != current) {
              await narration.setReciter(picked, language: services.prefs.language);
            }
          },
        ),
      ),
    );
  }
}

/// Shown above the player while a stretch repeats, with a way to stop.
class _Repeating extends StatelessWidget {
  const _Repeating({required this.narration});

  final Narration narration;

  @override
  Widget build(BuildContext context) {
    final stretch = narration.repeat!;
    final range = stretch.from == stretch.to ? '${stretch.from}' : context.t('range_n', {'from': stretch.from, 'to': stretch.to});
    final left = stretch.left < 0 ? context.t('repeat_always') : context.t('repeat_left', {'n': stretch.left});
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
      decoration: BoxDecoration(color: Palette.greenSoft, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Icon(Icons.repeat_rounded, size: 16, color: Palette.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.t('repeating', {'range': range})}. $left',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: Palette.greenDeep, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: narration.stopRepeat, child: Text(context.t('stop_repeat'), style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }
}

/// Picks where the repeat ends and how many times it plays.
class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({required this.from, required this.last});

  final int from;
  final int last;

  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<_RepeatSheet> {
  late int _to = widget.from;
  int _times = 3;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.t('repeat_title'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text(context.t('repeat_range', {'from': widget.from}), style: TextStyle(fontSize: 14, color: Palette.ink))),
                RoundButton(icon: Icons.remove_rounded, label: context.t('repeat_fewer'), onTap: _to > widget.from ? () => setState(() => _to--) : null),
                SizedBox(width: 44, child: Text('$_to', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.ink))),
                RoundButton(icon: Icons.add_rounded, label: context.t('repeat_more'), onTap: _to < widget.last ? () => setState(() => _to++) : null),
              ],
            ),
            const SizedBox(height: 12),
            Segmented<int>(
              height: 34,
              options: [(3, '3x'), (5, '5x'), (10, '10x'), (-1, context.t('repeat_always'))],
              value: _times,
              onChanged: (value) => setState(() => _times = value),
            ),
            const SizedBox(height: 14),
            BusyButton(label: context.t('repeat_start'), onPressed: () async => Navigator.of(context).pop((_to, _times))),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Palette.green),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
    );
  }
}
