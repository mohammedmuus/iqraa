import 'package:flutter/material.dart';

import '../core/narration.dart';
import '../core/scope.dart';
import '../core/strings.dart';
import '../theme.dart';

String speedText(double speed) => speed == speed.roundToDouble() ? '${speed.toStringAsFixed(1)}x' : '${speed}x';

/// The dark narration bar from the design. Given a [chapter] it starts that chapter's narration; without one it
/// controls whatever is playing.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, this.chapter, this.bookTitle = '', this.onOpen, this.closable = false});

  final Map<String, dynamic>? chapter;
  final String bookTitle;
  final VoidCallback? onOpen;
  final bool closable;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final narration = services.narration;
    final current = chapter == null || narration.isCurrent(chapter!['id']?.toString());
    if (chapter == null && narration.chapter == null) {
      return const SizedBox.shrink();
    }
    final title = current ? (narration.chapter?['title'] ?? '').toString() : context.t('listen_chapter');
    final Widget icon = current && narration.loading
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Icon(current && narration.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 24);
    return Container(
      height: 60,
      padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 6, 0),
      decoration: BoxDecoration(color: Palette.solid, borderRadius: BorderRadius.circular(30)),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: current && narration.playing ? context.t('pause') : context.t('play'),
            excludeSemantics: true,
            child: Material(
              color: Palette.green,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  if (current) {
                    narration.toggle();
                  } else {
                    narration.start(chapter!, bookTitle: bookTitle, language: services.prefs.language);
                  }
                },
                child: SizedBox(width: 44, height: 44, child: Center(child: icon)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    current && narration.failed ? context.t('audio_failed') : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const SizedBox(height: 7),
                  if (current) _Progress(narration: narration) else const SizedBox(height: 3),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (current)
            Semantics(
              button: true,
              label: context.t('speed'),
              child: Material(
                color: Colors.white,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: narration.nextSpeed,
                  child: SizedBox(
                    height: 44,
                    width: 58,
                    child: Center(child: Text(speedText(narration.speed), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Palette.onWhite))),
                  ),
                ),
              ),
            ),
          if (closable && current)
            IconButton(
              tooltip: context.t('stop_listening'),
              onPressed: narration.stop,
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.narration});

  final Narration narration;

  @override
  Widget build(BuildContext context) {
    final duration = narration.duration;
    return ValueListenableBuilder<Duration>(
      valueListenable: narration.position,
      builder: (context, value, _) {
        final total = duration.value.inMilliseconds;
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: total > 0 ? (value.inMilliseconds / total).clamp(0.0, 1.0) : 0,
            minHeight: 3,
            backgroundColor: const Color(0x2EFFFFFF),
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        );
      },
    );
  }
}
