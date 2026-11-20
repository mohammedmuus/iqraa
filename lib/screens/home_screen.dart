import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/layout.dart';
import '../core/reading_log.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/book_tile.dart';
import '../widgets/language_sheet.dart';
import '../widgets/ui.dart';
import 'account_screen.dart';
import 'book_screen.dart';
import 'qibla_screen.dart';
import 'reader_screen.dart';
import 'reminders_screen.dart';
import 'saved_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onSearch, required this.onLibrary, required this.onListen});

  final VoidCallback onSearch;
  final VoidCallback onLibrary;
  final VoidCallback onListen;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _home;
  List<Map<String, dynamic>> _subjects = const [];
  List<Map<String, dynamic>> _shelf = const [];
  String _subject = '';
  int _shown = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Opens with the copy kept on the phone and refreshes quietly behind it. Pulling down asks the server first.
  Future<void> _load({bool fresh = false}) async {
    final services = AppScope.read(context);
    setState(() => _error = null);
    void homeArrived(Map<String, dynamic> data) {
      if (mounted) {
        setState(() {
          _home = data;
          _shelf = _homeShelf();
        });
      }
    }

    void subjectsArrived(Map<String, dynamic> data) {
      if (mounted) {
        setState(() => _subjects = [for (final row in (data['results'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)]);
      }
    }

    try {
      final results = await Future.wait([
        services.cache.load('home', onUpdate: fresh ? null : homeArrived),
        services.cache.load('subjects', onUpdate: fresh ? null : subjectsArrived),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _home = results[0];
        _subjects = [for (final row in (results[1]['results'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)];
        _shelf = _homeShelf();
        _subject = '';
        _shown = 0;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  /// Books staff picked for the home screen, at most four; the newest books stand in until some are picked.
  List<Map<String, dynamic>> get _picks {
    final picked = _home?['featured_books'] as List? ?? const [];
    final rows = picked.isNotEmpty ? picked : (_home?['new_additions'] as List? ?? const []);
    return [for (final row in rows.take(4)) Map<String, dynamic>.from(row as Map)];
  }

  /// The large card opens on the Quran, then steps through the picked books.
  List<Map<String, dynamic>> _homeShelf() {
    final quran = _home?['quran'] ?? _home?['featured'];
    final rows = <Map<String, dynamic>>[if (quran is Map) Map<String, dynamic>.from(quran)];
    for (final row in _picks) {
      final book = Map<String, dynamic>.from(row as Map);
      if (rows.every((seen) => seen['id'] != book['id'])) {
        rows.add(book);
      }
    }
    return rows;
  }

  Future<void> _pickSubject(String slug) async {
    if (slug == _subject) {
      return;
    }
    setState(() {
      _subject = slug;
      _shown = 0;
    });
    if (slug.isEmpty) {
      setState(() => _shelf = _homeShelf());
      return;
    }
    try {
      final data = await AppScope.read(context).cache.load('books', query: {'subject': slug, 'page_size': '6'});
      if (mounted && _subject == slug) {
        setState(() => _shelf = [for (final row in (data['results'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)]);
      }
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  void _openReminders() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RemindersScreen()));
  }

  void _step(int by) {
    if (_shelf.isEmpty) {
      return;
    }
    setState(() => _shown = (_shown + by) % _shelf.length);
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final prefs = services.prefs;
    return PullRefresh(
      onRefresh: () => _load(fresh: true),
      child: ListView(
        padding: Layout.page(context, top: 8, bottom: 28),
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              const Wordmark(),
              const Spacer(),
              RoundButton(icon: Icons.search_rounded, label: context.t('search_library'), onTap: widget.onSearch),
              const SizedBox(width: 6),
              RoundButton(
                icon: Icons.explore_outlined,
                label: context.t('qibla'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QiblaScreen())),
              ),
              const SizedBox(width: 6),
              RoundButton(icon: Icons.notifications_none_rounded, label: context.t('reminders'), onTap: _openReminders),
              const SizedBox(width: 6),
              RoundButton(icon: Icons.person_outline_rounded, label: context.t('account'), onTap: () => openAccount(context)),
              const SizedBox(width: 6),
              // On narrow phones the language shows as a short code so the header fits on one line.
              Pill(
                label: MediaQuery.sizeOf(context).width < 380 ? prefs.language.toUpperCase() : Strings.names[prefs.language]!,
                onTap: () => pickLanguage(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!services.reminders.enabled && !services.reminders.promptDismissed) ...[
            Panel(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined, size: 20, color: Palette.green),
                  const SizedBox(width: 10),
                  Expanded(child: Text(context.t('reminders_prompt'), style: TextStyle(fontSize: 13, color: Palette.body))),
                  TextButton(onPressed: _openReminders, child: Text(context.t('set_up'))),
                  IconButton(
                    tooltip: context.t('dismiss'),
                    icon: Icon(Icons.close_rounded, size: 18, color: Palette.muted),
                    onPressed: services.reminders.dismissPrompt,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_home == null) ...[
            if (_error is ApiException && (_error as ApiException).isOffline && services.downloads.books.isNotEmpty)
              Panel(child: Text(context.t('offline_home'), textAlign: TextAlign.center))
            else
              LoadView(
                error: _error,
                onRetry: _load,
                skeleton: const Skeleton(
                  child: Column(
                    children: [
                      Bone(height: 220, radius: 24),
                      SizedBox(height: 16),
                      Row(children: [Expanded(child: Bone(height: 170, radius: 18)), SizedBox(width: 12), Expanded(child: Bone(height: 170, radius: 18))]),
                    ],
                  ),
                ),
              ),
          ] else ...[
            if (_subjects.isNotEmpty)
              Segmented<String>(
                options: [('', context.t('all')), for (final subject in _subjects.take(4)) (subject['slug'].toString(), subject['name'].toString())],
                value: _subject,
                onChanged: _pickSubject,
              ),
            const SizedBox(height: 10),
            if (_shelf.isEmpty)
              Panel(child: Text(context.t('no_subject_books'), textAlign: TextAlign.center))
            else
              _Featured(book: _shelf[_shown], position: _shown, total: _shelf.length, onStep: _step),
            if (_shelf.isNotEmpty) _Summary(book: _shelf[_shown], onListen: widget.onListen),
            if (prefs.lastRead != null) _ContinueReading(lastRead: prefs.lastRead!),
            if (services.readingLog.inProgress().isNotEmpty) _InProgress(log: services.readingLog),
            _Heading(first: context.t('featured_a'), second: context.t('featured_b'), onSeeAll: widget.onLibrary),
            AdaptiveGrid(
              minTileWidth: 150,
              spacing: 8,
              children: [for (final book in _picks) BookTile(book: book)],
            ),
          ],
          if (services.downloads.books.isNotEmpty) ...[
            _Heading(
              first: context.t('saved_a'),
              second: context.t('saved_b'),
              action: context.t('manage'),
              onSeeAll: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SavedScreen())),
            ),
            AdaptiveGrid(
              minTileWidth: 150,
              spacing: 8,
              children: [for (final book in services.downloads.books) BookTile(book: book, tag: context.t('saved_tag'))],
            ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.first, required this.second, this.onSeeAll, this.action});

  final String first;
  final String second;
  final VoidCallback? onSeeAll;

  /// The words on the link at the end of the heading. See all unless given.
  final String? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 22, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(text: '${first.toUpperCase()} ', style: TextStyle(color: Palette.quiet), children: [TextSpan(text: second.toUpperCase(), style: TextStyle(color: Palette.ink))]),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (onSeeAll != null) TextButton(onPressed: onSeeAll, child: Text(action ?? context.t('see_all'), style: TextStyle(fontSize: 12, color: Palette.ink))),
        ],
      ),
    );
  }
}

class _Featured extends StatelessWidget {
  const _Featured({required this.book, required this.position, required this.total, required this.onStep});

  final Map<String, dynamic> book;
  final int position;
  final int total;
  final ValueChanged<int> onStep;

  String get _word {
    final first = (book['title'] ?? '').toString().split(' ').first;
    return first.replaceFirst(RegExp(r'^(al|an|ar|as|at|ad|ash)-', caseSensitive: false), '').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final speed = details.primaryVelocity ?? 0;
        if (speed.abs() > 200) {
          onStep(speed < 0 ? 1 : -1);
        }
      },
      onTap: () => openBook(context, book),
      child: Container(
        height: 300,
        decoration: BoxDecoration(color: Palette.stone, borderRadius: BorderRadius.circular(24)),
        child: Stack(
          children: [
            Positioned(
              top: 12,
              left: 16,
              right: 12,
              child: Row(
                children: [
                  Text('${position + 1} / $total', style: TextStyle(fontSize: 11, color: Palette.muted)),
                  const Spacer(),
                  if (total > 1) ...[
                    RoundButton(icon: Icons.chevron_left_rounded, label: context.t('previous_book'), size: 30, onTap: () => onStep(-1)),
                    const SizedBox(width: 4),
                    RoundButton(icon: Icons.chevron_right_rounded, label: context.t('next_book'), size: 30, onTap: () => onStep(1)),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 52,
              left: 8,
              right: 8,
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_word, maxLines: 1, style: TextStyle(fontSize: 82, height: 1, fontWeight: FontWeight.w600, letterSpacing: -4, color: Palette.ink)),
                ),
              ),
            ),
            Positioned(top: 92, left: 0, right: 0, child: Center(child: AnimatedSwitcher(duration: const Duration(milliseconds: 240), child: BookCover(key: ValueKey(book['id']), book: book)))),
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Palette.line))),
                // The cover sits in the middle of this line, so each label keeps to its own side of it.
                child: Row(
                  children: [
                    Expanded(child: Text((book['author'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Palette.muted))),
                    const SizedBox(width: 144),
                    Expanded(
                      child: Text((book['arabic_title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, textDirection: TextDirection.rtl, style: TextStyle(fontFamily: AppTheme.arabic, fontSize: 12, color: Palette.muted)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.book, required this.onListen});

  final Map<String, dynamic> book;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final prefs = AppScope.of(context).prefs;
    final description = (book['description'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: '${book['title']}. ',
              style: TextStyle(fontWeight: FontWeight.w600, color: Palette.ink),
              children: [TextSpan(text: description.isNotEmpty ? description : (book['author'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w400, color: Palette.body))],
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.justify,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final code in const ['ar', 'sw', 'en']) ...[
                _LanguageDot(code: code.toUpperCase(), label: Strings.names[code]!, active: prefs.language == code, onTap: () => prefs.setLanguage(code)),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 4),
              TextButton(
                onPressed: () => openBook(context, book),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                child: Text(context.t('contents_link'), style: TextStyle(fontSize: 12, color: Palette.ink, decoration: TextDecoration.underline)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: BusyButton(label: context.t('read'), style: BusyStyle.light, onPressed: () async => openBook(context, book))),
              const SizedBox(width: 8),
              Expanded(
                flex: 13,
                child: BusyButton(
                  label: prefs.arabicOnly ? context.t('listen') : '${context.t('listen')}  |  ${context.t('lang_${prefs.language}')}',
                  style: BusyStyle.green,
                  onPressed: () async => onListen(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanguageDot extends StatelessWidget {
  const _LanguageDot({required this.code, required this.label, required this.active, required this.onTap});

  final String code;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Palette.greenSoft : Palette.surface,
            shape: BoxShape.circle,
            border: Border.all(color: active ? Palette.green : Palette.line),
          ),
          child: Text(code, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: active ? Palette.green : Palette.body)),
        ),
      ),
    );
  }
}

/// Books under way with how far the reader has come, and the days in a row they have read.
class _InProgress extends StatelessWidget {
  const _InProgress({required this.log});

  final ReadingLog log;

  @override
  Widget build(BuildContext context) {
    final books = log.inProgress();
    final streak = log.streak;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(context.t('in_progress'), style: Theme.of(context).textTheme.titleSmall)),
                if (streak > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Palette.greenSoft, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_fire_department_outlined, size: 14, color: Palette.green),
                        const SizedBox(width: 4),
                        Text(context.t(streak == 1 ? 'streak_day' : 'streak_days', {'n': streak}), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Palette.green)),
                      ],
                    ),
                  ),
              ],
            ),
            if (streak > 0 && !log.readToday)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(context.t('streak_keep'), style: TextStyle(fontSize: 11.5, color: Palette.muted))),
            const SizedBox(height: 6),
            for (final book in books) _ProgressRow(book: book),
          ],
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.book});

  final Map<String, dynamic> book;

  @override
  Widget build(BuildContext context) {
    final quran = book['quran'] == true;
    final done = (book['done'] as List? ?? const []).length;
    final total = (book['total'] as num?)?.toInt() ?? 0;
    final ayat = (book['ayat'] as num?)?.toInt() ?? 0;
    final parts = [
      if (total > 0) context.t(quran ? 'surahs_of' : 'chapters_of', {'n': done, 'total': total}) else context.t(quran ? 'surahs_n' : 'chapters_n', {'n': done}),
      if (quran && ayat > 0) context.t('ayat_read', {'n': ayat}),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          chapterId: book['chapter'].toString(),
          bookTitle: book['title'].toString(),
          total: total,
          startAt: (book['paragraph'] as num?)?.toInt(),
        ),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(book['title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Palette.ink))),
                Icon(Icons.chevron_right_rounded, size: 18, color: Palette.muted),
              ],
            ),
            Text((book['chapter_title'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Palette.muted)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => LinearProgressIndicator(value: value, minHeight: 5, backgroundColor: Palette.canvas),
              ),
            ),
            const SizedBox(height: 4),
            Text(parts.join('  |  '), style: TextStyle(fontSize: 11, color: Palette.body)),
          ],
        ),
      ),
    );
  }
}

class _ContinueReading extends StatelessWidget {
  const _ContinueReading({required this.lastRead});

  final Map<String, dynamic> lastRead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: Palette.solid,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(
              chapterId: lastRead['chapter'].toString(),
              bookTitle: lastRead['book_title'].toString(),
              startAt: (lastRead['paragraph'] as num?)?.toInt(),
            ),
          )),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.t('continue_reading'), style: TextStyle(fontSize: 11, color: Palette.goldLight)),
                      const SizedBox(height: 3),
                      Text(lastRead['book_title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                      Text(lastRead['chapter_title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF))),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
