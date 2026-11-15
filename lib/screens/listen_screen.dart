import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/layout.dart';
import '../core/narration.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';
import '../widgets/book_tile.dart';
import '../widgets/player_bar.dart';
import '../widgets/ui.dart';
import 'reader_screen.dart';

class ListenScreen extends StatefulWidget {
  const ListenScreen({super.key});

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  List<Map<String, dynamic>>? _books;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      void show(Map<String, dynamic> data) {
        if (mounted) {
          setState(() => _books = [for (final row in (data['results'] as List? ?? const [])) Map<String, dynamic>.from(row as Map)]);
        }
      }

      show(await AppScope.read(context).cache.load('books', query: {'audio': '1', 'page_size': '50'}, onUpdate: show));
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _resume(Map<String, dynamic> last) async {
    final services = AppScope.read(context);
    try {
      final chapter = await services.chapter(last['chapter'].toString());
      await services.narration.start(
        chapter,
        bookTitle: last['book_title'].toString(),
        language: services.prefs.language,
        from: Duration(milliseconds: (last['position_ms'] as num?)?.toInt() ?? 0),
      );
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, context.describe(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final narration = AppScope.of(context).narration;
    final last = narration.lastListened;
    return RefreshIndicator(
      color: Palette.green,
      onRefresh: _load,
      child: ListView(
        padding: Layout.page(context, top: 16, bottom: 28),
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: DisplayTitle(context.t('listen_a'), second: context.t('listen_b'))),
          const SizedBox(height: 14),
          if (narration.chapter != null)
            _NowPlaying(narration: narration)
          else if (last != null)
            Material(
              color: Palette.solid,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _resume(last),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.t('continue_listening'), style: TextStyle(fontSize: 11, color: Palette.goldLight)),
                            const SizedBox(height: 3),
                            Text(last['book_title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                            Text(last['chapter_title'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF))),
                          ],
                        ),
                      ),
                      Icon(Icons.play_circle_fill_rounded, color: Palette.green, size: 40),
                    ],
                  ),
                ),
              ),
            )
          else
            Panel(child: Text(context.t('nothing_playing'), textAlign: TextAlign.center)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 22, 8, 8),
            child: Text.rich(
              TextSpan(
                text: '${context.t('books_audio_a').toUpperCase()} ',
                style: TextStyle(color: Palette.quiet),
                children: [TextSpan(text: context.t('books_audio_b').toUpperCase(), style: TextStyle(color: Palette.ink))],
              ),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          if (_books == null)
            LoadView(error: _error, onRetry: _load, skeleton: const SkeletonRows(rows: 5))
          else if (_books!.isEmpty)
            Panel(child: Text(context.t('no_audio_books'), textAlign: TextAlign.center))
          else
            AdaptiveGrid(minTileWidth: 150, spacing: 8, children: [for (final book in _books!) BookTile(book: book, tag: context.t('audio'))]),
        ],
      ),
    );
  }
}

String _clock(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return value.inHours > 0 ? '${value.inHours}:${minutes.remainder(60).toString().padLeft(2, '0')}:$seconds' : '$minutes:$seconds';
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.narration});

  final Narration narration;

  @override
  Widget build(BuildContext context) {
    final narrator = (narration.track?['narrator'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(color: Palette.solid, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('now_playing'), style: TextStyle(fontSize: 11, color: Palette.goldLight)),
          const SizedBox(height: 4),
          Text(narration.bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
          Text((narration.chapter?['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xCCFFFFFF))),
          if (narrator.isNotEmpty) Text(context.t('narrated_by', {'name': narrator}), style: const TextStyle(fontSize: 11.5, color: Color(0x99FFFFFF))),
          if (narration.failed) ...[
            const SizedBox(height: 8),
            Text(context.t('audio_failed'), style: TextStyle(fontSize: 12.5, color: Palette.goldLight)),
          ],
          const SizedBox(height: 8),
          ValueListenableBuilder<Duration>(
            valueListenable: narration.position,
            builder: (context, position, _) {
              final total = narration.duration.value;
              final max = total.inMilliseconds > 0 ? total.inMilliseconds.toDouble() : 1.0;
              return Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: const Color(0x2EFFFFFF),
                      thumbColor: Palette.green,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: position.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                      max: max,
                      onChanged: (value) => narration.seek(Duration(milliseconds: value.round())),
                    ),
                  ),
                  Row(
                    children: [
                      Text(_clock(position), style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF))),
                      const Spacer(),
                      Text(_clock(total), style: const TextStyle(fontSize: 11, color: Color(0x99FFFFFF))),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(tooltip: context.t('back_10'), onPressed: () => narration.skip(-10), icon: const Icon(Icons.replay_10_rounded, color: Colors.white)),
              const SizedBox(width: 10),
              Material(
                color: Palette.green,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: narration.toggle,
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: Semantics(
                      label: narration.playing ? context.t('pause') : context.t('play'),
                      child: Icon(narration.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 32),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(tooltip: context.t('forward_10'), onPressed: () => narration.skip(10), icon: const Icon(Icons.forward_10_rounded, color: Colors.white)),
              const SizedBox(width: 6),
              TextButton(
                onPressed: narration.nextSpeed,
                style: TextButton.styleFrom(backgroundColor: Colors.white, shape: const StadiumBorder(), minimumSize: const Size(56, 40)),
                child: Text(speedText(narration.speed), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.onWhite)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PairRow(
            first: BusyButton(
              label: context.t('open_reader'),
              style: BusyStyle.light,
              onPressed: () async {
                final chapter = narration.chapter;
                if (chapter != null) {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(chapterId: chapter['id'].toString(), bookTitle: narration.bookTitle)));
                }
              },
            ),
            second: BusyButton(label: context.t('stop_listening'), style: BusyStyle.green, onPressed: narration.stop),
          ),
        ],
      ),
    );
  }
}
