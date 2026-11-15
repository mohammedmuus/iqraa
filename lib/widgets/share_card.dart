import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/strings.dart';
import '../theme.dart';
import 'ui.dart';

/// Shows a verse or passage as an image card, then shares it, for example to a WhatsApp status.
Future<void> sharePassage(BuildContext context, {required String arabic, required String translation, required String reference}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(arabic: arabic, translation: translation, reference: reference),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.arabic, required this.translation, required this.reference});

  final String arabic;
  final String translation;
  final String reference;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final GlobalKey _card = GlobalKey();

  Future<void> _share() async {
    final boundary = _card.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      return;
    }
    // Saved at 1080 pixels wide, the size status updates and chats show best.
    final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null || !mounted) {
      return;
    }
    final folder = await getTemporaryDirectory();
    final file = File('${folder.path}/iqraa-${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    if (!mounted) {
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: context.t('share_from', {'ref': widget.reference}),
      sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    ));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width - 32, 340.0);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            Text(context.t('share_image'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            RepaintBoundary(
              key: _card,
              child: SizedBox(width: width, height: width * 1.25, child: PassageCard(arabic: widget.arabic, translation: widget.translation, reference: widget.reference)),
            ),
            const SizedBox(height: 14),
            SizedBox(width: width, child: BusyButton(label: context.t('share_now'), onPressed: _share)),
          ],
        ),
      ),
    );
  }
}

/// The card itself: deep green with a gold frame, the Arabic, the translation and where it comes from.
class PassageCard extends StatelessWidget {
  const PassageCard({super.key, required this.arabic, required this.translation, required this.reference});

  final String arabic;
  final String translation;
  final String reference;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = constraints.maxWidth / 340;
        final long = arabic.length + translation.length;
        final arabicSize = (long < 220 ? 24.0 : long < 520 ? 19.0 : 15.0) * unit;
        final textSize = (long < 220 ? 13.5 : long < 520 ? 11.5 : 9.5) * unit;
        return Container(
          color: Palette.brandGreenDeep,
          padding: EdgeInsets.all(12 * unit),
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: Palette.gold.withValues(alpha: 0.7), width: 1.2 * unit), borderRadius: BorderRadius.circular(14 * unit)),
            padding: EdgeInsets.fromLTRB(18 * unit, 20 * unit, 18 * unit, 14 * unit),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (arabic.isNotEmpty)
                        Flexible(
                          child: Text(
                            arabic,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            overflow: TextOverflow.fade,
                            style: TextStyle(fontFamily: AppTheme.arabic, fontSize: arabicSize, height: 1.8, color: Palette.goldLight),
                          ),
                        ),
                      if (arabic.isNotEmpty && translation.isNotEmpty) SizedBox(height: 12 * unit),
                      if (translation.isNotEmpty)
                        Flexible(
                          child: Text(
                            translation,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.fade,
                            style: TextStyle(fontSize: textSize, height: 1.55, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 10 * unit),
                Text(reference, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 10.5 * unit, color: Palette.goldLight)),
                SizedBox(height: 8 * unit),
                Center(child: Wordmark(size: 15 * unit, colour: Colors.white, mark: Palette.gold)),
              ],
            ),
          ),
        );
      },
    );
  }
}
