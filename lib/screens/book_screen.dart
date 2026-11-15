import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/layout.dart';
import '../core/quran.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'reader_screen.dart';

void openBook(BuildContext context, Map<String, dynamic> book) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BookScreen(bookId: book['id'].toString(), preview: book)));
}

class BookScreen extends StatefulWidget {
  const BookScreen({super.key, required this.bookId, this.preview = const {}});

  final String bookId;
  final Map<String, dynamic> preview;

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  Map<String, dynamic>? _book;
  Object? _error;

  /// What the reader typed to find a chapter: a number or words from its title.
  String _find = '';

  /// Books longer than this get a box to find a chapter.
  static const _findFrom = 12;

  List<Map<String, dynamic>> _shown(List<Map<String, dynamic>> chapters) {
    final words = _find.trim().toLowerCase();
    if (words.isEmpty) {
      return chapters;
    }
    final number = int.tryParse(words);
    if (number != null) {
      return [for (final c in chapters) if (c['number'].toString().startsWith(words)) c];
    }
    return [
      for (final c in chapters)
        if ((c['title'] ?? '').toString().toLowerCase().contains(words) || (c['arabic_title'] ?? '').toString().contains(_find.trim())) c,
    ];
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // A copy kept on the phone opens at once; newer contents replace it quietly when they arrive.
      final data = await AppScope.read(context).book(widget.bookId, onUpdate: (fresh) {
        if (mounted) {
          setState(() => _take(fresh));
        }
      });
      if (mounted) {
        setState(() => _take(data));
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  List<Map<String, dynamic>> _chapters = const [];

  void _take(Map<String, dynamic> data) {
    _book = data;
    _chapters = [for (final row in (data['chapters'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
  }

  void _read(Map<String, dynamic> chapter, {int? at}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(chapterId: chapter['id'].toString(), bookTitle: (_book?['title'] ?? '').toString(), author: (_book?['author'] ?? '').toString(), total: _chapters.length, startAt: at),
    ));
  }

  /// Opens a surah at an ayah, from the Go to sheet.
  void _goTo(int surah, int? ayah) {
    final chapter = _chapters.where((c) => c['number'] == surah).firstOrNull;
    if (chapter != null) {
      _read(chapter, at: ayah);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final book = _book ?? widget.preview;
    final chapters = _chapters;
    final shown = _shown(chapters);
    final lastRead = services.prefs.lastRead;
    final resume = lastRead != null && lastRead['book'] == widget.bookId ? chapters.where((c) => c['id'] == lastRead['chapter']).firstOrNull : null;
    final translation = services.prefs.translation;
    final description = (book['description'] ?? '').toString();
    final edition = (book['source_edition'] ?? '').toString();
    final rights = (book['rights_note'] ?? '').toString();
    return Scaffold(
      body: PatternBackground(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: Layout.page(context, top: 8, bottom: 0),
                sliver: SliverList.list(
                  children: [
                    Row(children: [RoundButton(icon: Icons.arrow_back_rounded, label: context.t('back'), onTap: () => Navigator.of(context).maybePop())]),
                    const SizedBox(height: 12),
                    Container(
                      height: 240,
                      decoration: BoxDecoration(color: Palette.stone, borderRadius: BorderRadius.circular(24)),
                      alignment: Alignment.center,
                      child: BookCover(book: book),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DisplayTitle((book['title'] ?? '').toString(), second: (book['author'] ?? '').toString(), size: 30),
                          if ((book['arabic_title'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            SizedBox(width: double.infinity, child: ArabicText(book['arabic_title'].toString(), size: 24, color: Palette.body)),
                          ],
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(description, textAlign: TextAlign.justify),
                          ],
                          if (edition.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(context.t('arabic_text', {'edition': edition}), style: Theme.of(context).textTheme.bodySmall),
                          ],
                          if (rights.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(rights, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_book == null)
                      LoadView(error: _error, onRetry: _load, skeleton: const SkeletonRows(rows: 8))
                    else if (chapters.isEmpty)
                      Panel(child: Text(context.t('chapters_preparing'), textAlign: TextAlign.center))
                    else ...[
                      BusyButton(
                        label: resume != null ? context.t('continue_at', {'title': resume['title'] ?? ''}) : context.t('start_reading'),
                        onPressed: () async => resume != null ? _read(resume, at: services.prefs.placeIn(resume['id'].toString())) : _read(chapters.first),
                      ),
                      if (_book?['quran'] == true) ...[
                        const SizedBox(height: 8),
                        BusyButton(
                          label: context.t('go_to'),
                          style: BusyStyle.light,
                          onPressed: () async {
                            final target = await showModalBottomSheet<(int, int?)>(
                              context: context,
                              backgroundColor: Palette.surface,
                              showDragHandle: true,
                              isScrollControlled: true,
                              builder: (_) => const _GoToSheet(),
                            );
                            if (target != null && mounted) {
                              _goTo(target.$1, target.$2);
                            }
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      _SaveForOffline(bookId: widget.bookId, title: (book['title'] ?? '').toString()),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text.rich(
                          TextSpan(
                            text: '${context.t('contents_a').toUpperCase()} ',
                            style: TextStyle(color: Palette.quiet),
                            children: [TextSpan(text: context.t('contents_b').toUpperCase(), style: TextStyle(color: Palette.ink))],
                          ),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (chapters.length > _findFrom) ...[
                        TextField(
                          onChanged: (value) => setState(() => _find = value),
                          textInputAction: TextInputAction.search,
                          maxLength: 60,
                          decoration: InputDecoration(
                            hintText: context.t('find_chapter'),
                            counterText: '',
                            isDense: true,
                            prefixIcon: Icon(Icons.search_rounded, size: 19, color: Palette.muted),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (shown.isEmpty) Panel(child: Text(context.t('no_chapter_match'), textAlign: TextAlign.center)),
                      ],
                    ],
                  ],
                ),
              ),
              // Long books have hundreds of chapters, so rows are only built as they scroll into view.
              if (shown.isNotEmpty)
                SliverPadding(
                  padding: Layout.page(context, top: 0, bottom: 28),
                  sliver: SliverList.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: Palette.surface,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(i == 0 ? 20 : 0),
                          bottom: Radius.circular(i == shown.length - 1 ? 20 : 0),
                        ),
                      ),
                      child: Column(
                        children: [
                          if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                          _ChapterRow(
                            chapter: shown[i],
                            translation: translation,
                            current: resume?['id'] == shown[i]['id'],
                            onTap: () => resume?['id'] == shown[i]['id'] ? _read(shown[i], at: services.prefs.placeIn(shown[i]['id'].toString())) : _read(shown[i]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.chapter, required this.translation, required this.current, required this.onTap});

  final Map<String, dynamic> chapter;

  /// The reader's translation language, or null when they read Arabic only.
  final String? translation;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final translated = translation != null && (chapter['translated'] as List? ?? const []).contains(translation);
    final audio = (chapter['audio'] as List? ?? const []).isNotEmpty;
    final arabic = (chapter['arabic_title'] ?? '').toString();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: current ? Palette.green : Palette.stone, shape: BoxShape.circle),
              child: Text('${chapter['number']}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: current ? Colors.white : Palette.ink)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((chapter['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Palette.ink)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (translation != null) translated ? context.t('lang_$translation') : context.t('arabic_only_now'),
                      if (audio) context.t('audio'),
                    ].join('  |  '),
                    style: TextStyle(fontSize: 11, color: Palette.muted),
                  ),
                ],
              ),
            ),
            if (arabic.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(child: ArabicText(arabic, size: 15, color: Palette.muted, height: 1.4, maxLines: 1)),
            ],
            if (audio) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.headphones_outlined, size: 16, color: Palette.green)),
          ],
        ),
      ),
    );
  }
}

/// Saves the whole book, text and narration, so it reads and plays without internet.
class _SaveForOffline extends StatelessWidget {
  const _SaveForOffline({required this.bookId, required this.title});

  final String bookId;
  final String title;

  /// The result is shown wherever the reader is by then, since saving carries on after they leave this page.
  Future<void> _save(BuildContext context) async {
    final services = AppScope.read(context);
    final messenger = services.messengerKey.currentState;
    String t(String key) => Strings.of(services.prefs.language, key, {'title': title});
    try {
      final saved = await services.downloads.save(bookId);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t(saved ? 'saved_book' : 'save_cancelled'))));
    } on Object {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t('save_stopped'))));
    }
  }

  Future<void> _remove(BuildContext context) async {
    await AppScope.read(context).downloads.remove(bookId);
    if (context.mounted) {
      showMessage(context, context.t('removed_done'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloads = AppScope.of(context).downloads;
    final share = downloads.progress[bookId];
    if (share != null) {
      return Panel(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(context.t('saving', {'n': (share * 100).round()}), style: TextStyle(fontSize: 12.5, color: Palette.body))),
                TextButton(
                  onPressed: () => downloads.stop(bookId),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Palette.bad),
                  child: Text(context.t('stop_saving'), style: const TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: share, minHeight: 4, backgroundColor: Palette.stone),
              ),
            ),
          ],
        ),
      );
    }
    if (downloads.has(bookId)) {
      return Panel(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Icon(Icons.download_done_rounded, size: 18, color: Palette.green),
            const SizedBox(width: 8),
            Expanded(child: Text(context.t('saved_here'), maxLines: 2, style: TextStyle(fontSize: 12.5, color: Palette.ink))),
            TextButton(onPressed: () => _remove(context), child: Text(context.t('remove'), style: TextStyle(color: Palette.bad, fontSize: 12.5))),
          ],
        ),
      );
    }
    return BusyButton(label: context.t('save_offline'), style: BusyStyle.light, onPressed: () => _save(context));
  }
}

/// Go to a surah and ayah, or to the start of a juz.
class _GoToSheet extends StatefulWidget {
  const _GoToSheet();

  @override
  State<_GoToSheet> createState() => _GoToSheetState();
}

class _GoToSheetState extends State<_GoToSheet> {
  bool _byJuz = false;
  final TextEditingController _surah = TextEditingController();
  final TextEditingController _ayah = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _surah.dispose();
    _ayah.dispose();
    super.dispose();
  }

  void _submit() {
    final surah = int.tryParse(_surah.text.trim());
    final ayah = int.tryParse(_ayah.text.trim());
    if (surah == null || surah < 1 || surah > 114) {
      setState(() => _problem = context.t('bad_surah'));
      return;
    }
    Navigator.of(context).pop((surah, ayah != null && ayah > 0 ? ayah : null));
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.t('go_to'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Segmented<bool>(
              height: 34,
              options: [(false, context.t('go_surah')), (true, context.t('go_juz'))],
              value: _byJuz,
              onChanged: (value) => setState(() => _byJuz = value),
            ),
            const SizedBox(height: 12),
            if (_byJuz)
              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width < 360 ? 5 : 6,
                shrinkWrap: true,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.25,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < juzStarts.length; i++)
                    Material(
                      color: Palette.canvas,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.of(context).pop((juzStarts[i].$1, juzStarts[i].$2)),
                        child: Center(child: Text('${i + 1}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Palette.ink))),
                      ),
                    ),
                ],
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _surah,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: InputDecoration(labelText: context.t('surah_number'), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ayah,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(labelText: context.t('ayah_number'), isDense: true),
                    ),
                  ),
                ],
              ),
              if (_problem != null) ...[
                const SizedBox(height: 6),
                Text(_problem!, style: TextStyle(fontSize: 12.5, color: Palette.bad)),
              ],
              const SizedBox(height: 12),
              BusyButton(label: context.t('go'), onPressed: () async => _submit()),
            ],
          ],
        ),
      ),
    );
  }
}
