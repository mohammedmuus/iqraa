import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/strings.dart';
import '../theme.dart';
import 'skeleton.dart';

export 'skeleton.dart';

/// The faint book drawings from the website behind every screen, larger on wide screens.
class PatternBackground extends StatelessWidget {
  const PatternBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.canvas,
        image: DecorationImage(
          image: const AssetImage('assets/images/pattern.png'),
          // In the dark look the drawings turn a soft off-white so they still show.
          colorFilter: Palette.dark ? const ColorFilter.mode(Color(0x8CEDEBE6), BlendMode.srcIn) : null,
          repeat: ImageRepeat.repeat,
          alignment: Alignment.topCenter,
          // The tile is drawn at 720px for 240 logical pixels, or 320 on wide screens.
          scale: wide ? 2.25 : 3,
        ),
      ),
      child: child,
    );
  }
}

/// Uppercase display heading in two tones, as on the website: "SUPPORT / THE LIBRARY".
class DisplayTitle extends StatelessWidget {
  const DisplayTitle(this.first, {super.key, this.second = '', this.size = 34});

  final String first;
  final String second;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Tight tracking suits the Latin display type but breaks the joins between Arabic letters.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final style = Theme.of(context).textTheme.displaySmall!.copyWith(fontSize: rtl ? size * 0.9 : size, letterSpacing: rtl ? 0 : -size * 0.045, height: rtl ? 1.3 : null);
    return Text.rich(
      TextSpan(
        text: first.toUpperCase(),
        children: [if (second.isNotEmpty) TextSpan(text: '\n${second.toUpperCase()}', style: TextStyle(color: Palette.quiet))],
      ),
      style: style,
    );
  }
}

class ArabicText extends StatelessWidget {
  const ArabicText(this.text, {super.key, this.size = 22, this.color, this.height = 1.7, this.align = TextAlign.right, this.maxLines, this.number});

  final String text;
  final double size;

  /// When given, a ringed number in Arabic digits closes the passage, like an ayah marker.
  final int? number;

  /// Ink unless given.
  final Color? color;
  final double height;
  final TextAlign align;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: AppTheme.arabic, fontSize: size, height: height, color: color ?? Palette.ink);
    final mark = number;
    if (mark == null) {
      return Text(text, textDirection: TextDirection.rtl, textAlign: align, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis, style: style);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$text '),
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: AyahMark(mark, size: size)),
        ],
      ),
      textDirection: TextDirection.rtl,
      textAlign: align,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// A small gold ring with a number in Arabic digits, closing a passage of Arabic text.
class AyahMark extends StatelessWidget {
  const AyahMark(this.number, {super.key, this.size = 22});

  final int number;

  /// The size of the Arabic text it sits in.
  final double size;

  static String digits(int value) => value.toString().split('').map((d) => '٠١٢٣٤٥٦٧٨٩'[int.parse(d)]).join();

  @override
  Widget build(BuildContext context) {
    final height = size * 1.05;
    return Semantics(
      label: '$number',
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minWidth: height),
        height: height,
        padding: EdgeInsets.symmetric(horizontal: size * 0.18),
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: Palette.gold, width: 1.3), borderRadius: BorderRadius.circular(999)),
        child: Text(digits(number), style: TextStyle(fontFamily: AppTheme.arabic, fontSize: size * 0.5, height: 1, color: Palette.green)),
      ),
    );
  }
}

/// A book cover: the uploaded image when there is one, otherwise the Arabic title on the book's colour.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.width = 132});

  final Map<String, dynamic> book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 4 / 3;
    final small = width < 80;
    final image = (book['cover_image'] ?? '').toString();
    final radius = BorderRadius.horizontal(left: Radius.circular(small ? 2 : 3), right: Radius.circular(small ? 4 : 7));
    final shadow = [BoxShadow(color: const Color(0x380B0B0C), blurRadius: small ? 14 : 36, offset: Offset(0, small ? 8 : 22))];
    if (image.isNotEmpty) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
        clipBehavior: Clip.antiAlias,
        child: Image.network(image, fit: BoxFit.cover, errorBuilder: (_, _, _) => _plain(height, radius, shadow, small)),
      );
    }
    return _plain(height, radius, shadow, small);
  }

  /// A bound book drawn in code: spine and hinge on the left, light from the top, faint cloth grain,
  /// a double gold frame and the page block showing on the fore edge.
  Widget _plain(double height, BorderRadius radius, List<BoxShadow> shadow, bool small) {
    final arabic = (book['arabic_title'] ?? '').toString();
    final title = (book['title'] ?? '').toString();
    final author = (book['author'] ?? '').toString();
    final colour = Color(colourValue(book['cover_colour'], 0xFF1F6B4A));
    final spine = width * 0.12;
    final frame = Palette.gold.withValues(alpha: 0.55);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Pages on the fore edge.
          Positioned(
            top: 3,
            bottom: 3,
            right: small ? -2 : -4,
            width: small ? 2 : 4,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF4EFE2), Color(0xFFE3DCC9), Color(0xFFF4EFE2), Color(0xFFE3DCC9)],
                  stops: [0, 0.33, 0.66, 1],
                  tileMode: TileMode.repeated,
                ),
                boxShadow: [BoxShadow(color: Color(0x2E0B0B0C), blurRadius: 2, offset: Offset(1, 1))],
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: shadow,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(colour, Colors.white, 0.08)!, Color.lerp(colour, Colors.black, 0.22)!],
                ),
              ),
            ),
          ),
          // Light from the top.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: RadialGradient(
                  center: const Alignment(-0.5, -1.1),
                  radius: 1.2,
                  colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          // Spine and hinge.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: spine,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(left: radius.topLeft),
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.32),
                    Colors.black.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.14),
                    Colors.black.withValues(alpha: 0.16),
                    Colors.black.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.5, 0.62, 0.75, 1],
                ),
              ),
            ),
          ),
          // Double gold frame.
          Positioned(
            left: width * 0.16,
            right: width * 0.07,
            top: height * 0.07,
            bottom: height * 0.07,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: frame, width: small ? 0.6 : 1), borderRadius: BorderRadius.circular(2)),
              child: small
                  ? null
                  : Padding(
                      padding: const EdgeInsets.all(3),
                      child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: Palette.gold.withValues(alpha: 0.28), width: 1))),
                    ),
            ),
          ),
          Positioned(
            left: width * 0.18,
            right: width * 0.09,
            top: height * 0.09,
            bottom: height * 0.09,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!small) Container(width: 26, height: 1, color: Palette.gold),
                SizedBox(height: small ? 0 : 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: arabic.isNotEmpty
                        ? ArabicText(arabic, size: small ? 14 : 28, color: Palette.canvas, height: 1.2, align: TextAlign.center)
                        : Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: small ? 9 : 16, color: Palette.canvas, fontWeight: FontWeight.w600)),
                  ),
                ),
                if (!small && author.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(author.toUpperCase(), maxLines: 2, textAlign: TextAlign.center, style: TextStyle(fontSize: 8, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: Palette.goldLight)),
                ],
                if (!small) ...[
                  const SizedBox(height: 10),
                  Container(width: 26, height: 1, color: Palette.gold),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Round white icon button used in screen headers.
class RoundButton extends StatelessWidget {
  const RoundButton({super.key, required this.icon, required this.label, required this.onTap, this.size = 36});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Palette.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: 17, color: onTap == null ? Palette.quiet : Palette.ink)),
        ),
      ),
    );
  }
}

/// Small rounded pill button, dark or light.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.onTap, this.dark = true, this.height = 36});

  final String label;
  final VoidCallback? onTap;
  final bool dark;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: dark ? Palette.solid : Palette.surface,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dark ? Colors.white : Palette.ink)),
        ),
      ),
    );
  }
}

/// Segmented choice that always fits the width: every option shares the row, labels shrink with ellipsis.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged, this.height = 32});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(height)),
      child: Row(
        children: [
          for (final (option, label) in options)
            Expanded(
              child: Semantics(
                selected: option == value,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: height,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: option == value ? Palette.solid : Colors.transparent, borderRadius: BorderRadius.circular(height / 2)),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, fontWeight: option == value ? FontWeight.w600 : FontWeight.w500, color: option == value ? Colors.white : Palette.ink),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full width button that shows "Please wait" and blocks repeat taps until its task finishes.
class BusyButton extends StatefulWidget {
  const BusyButton({super.key, required this.label, required this.onPressed, this.style = BusyStyle.dark, this.expand = true});

  final String label;
  final Future<void> Function()? onPressed;
  final BusyStyle style;
  final bool expand;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

enum BusyStyle { dark, green, light }

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (widget.style) {
      BusyStyle.dark => (Palette.solid, Colors.white),
      BusyStyle.green => (Palette.green, Colors.white),
      BusyStyle.light => (Palette.surface, Palette.ink),
    };
    final button = TextButton(
      onPressed: widget.onPressed == null || _busy ? null : _run,
      style: TextButton.styleFrom(
        backgroundColor: background,
        disabledBackgroundColor: background.withValues(alpha: 0.6),
        foregroundColor: foreground,
        disabledForegroundColor: foreground.withValues(alpha: 0.8),
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, fontFamily: AppTheme.sans),
      ),
      child: Text(_busy ? context.t('please_wait') : widget.label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return widget.expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.radius = 20});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// The card colour, white in the light look unless given.
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: color ?? Palette.surface, borderRadius: BorderRadius.circular(radius)),
      child: child,
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.dot});

  final String label;

  /// Green unless given.
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: dot ?? Palette.green, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500, color: Palette.ink)),
        ],
      ),
    );
  }
}

class ErrorNote extends StatelessWidget {
  const ErrorNote(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: Palette.badSoft, borderRadius: BorderRadius.circular(14)),
      child: Text(message!, style: TextStyle(color: Palette.bad, fontSize: 13)),
    );
  }
}

class LoadView extends StatelessWidget {
  const LoadView({super.key, this.error, this.onRetry, this.skeleton});

  final Object? error;
  final VoidCallback? onRetry;

  /// What shows while loading, laid out like the content. Rows of a list unless given.
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return skeleton ?? const SkeletonRows(rows: 4);
    }
    final message = context.describe(error);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (onRetry != null) TextButton(onPressed: onRetry, child: Text(context.t('try_again'), style: TextStyle(color: Palette.green))),
        ],
      ),
    );
  }
}

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// A short moment when something is finished, such as a daily goal or a chapter. It closes by itself.
Future<void> celebrate(BuildContext context, String title, {String body = ''}) {
  final navigator = Navigator.of(context);
  var open = true;
  Future<void>.delayed(const Duration(milliseconds: 1800), () {
    if (open && navigator.mounted) {
      navigator.pop();
    }
  });
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: const Color(0x330B0B0C),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, _) => Center(
      child: Material(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) => Transform.scale(scale: value, child: child),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: Palette.greenSoft, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded, color: Palette.green, size: 36),
                  ),
                ),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Palette.ink)),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Palette.muted)),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
  ).whenComplete(() => open = false);
}

/// The iqraa wordmark, ending in a small open book where a full stop would be.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22, this.colour, this.mark});

  final double size;

  /// The words and the book, ink and green unless given.
  final Color? colour;
  final Color? mark;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'iqraa',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          text: 'iqraa',
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: size * 0.07),
                child: CustomPaint(size: Size(size * 0.34, size * 0.25), painter: BookMarkPainter(mark ?? Palette.green)),
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, letterSpacing: -size * 0.036, color: colour ?? Palette.ink, height: 1.2),
      ),
    );
  }
}

/// Two open pages on a 100 by 72 grid, the same shape as the app icon and the website.
class BookMarkPainter extends CustomPainter {
  const BookMarkPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 72);
    final paint = Paint()..color = colour;
    final left = Path()
      ..moveTo(47, 70)
      ..cubicTo(36, 62, 20, 59, 3, 61)
      ..lineTo(3, 8)
      ..cubicTo(20, 6, 36, 9, 47, 17)
      ..close();
    final right = Path()
      ..moveTo(53, 70)
      ..cubicTo(64, 62, 80, 59, 97, 61)
      ..lineTo(97, 8)
      ..cubicTo(80, 6, 64, 9, 53, 17)
      ..close();
    canvas
      ..drawPath(left, paint)
      ..drawPath(right, paint);
  }

  @override
  bool shouldRepaint(BookMarkPainter old) => old.colour != colour;
}

/// Pull down to reload. Shows the phone's own spinner (iPhone or Android) and lets the page be pulled
/// even when it is too short to scroll.
class PullRefresh extends StatelessWidget {
  const PullRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return RefreshIndicator.adaptive(
      color: Palette.green,
      onRefresh: onRefresh,
      notificationPredicate: (notification) => notification.depth == 0 && notification.metrics.axis == Axis.vertical,
      child: ScrollConfiguration(
        behavior: behavior.copyWith(physics: AlwaysScrollableScrollPhysics(parent: behavior.getScrollPhysics(context))),
        child: child,
      ),
    );
  }
}

/// A compact search field for a list, with a button to clear it.
class SearchBox extends StatelessWidget {
  const SearchBox({super.key, required this.controller, required this.hint, required this.onChanged});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        maxLength: 40,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          counterText: '',
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: Palette.muted),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: context.t('clear'),
                  icon: const Icon(Icons.close_rounded, size: 17),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Previous and next page buttons with the page number between them. Hidden when there is one page.
class Pager extends StatelessWidget {
  const Pager({super.key, required this.page, required this.pages, required this.onPage});

  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (pages <= 1) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RoundButton(icon: Icons.chevron_left_rounded, label: context.t('previous_page'), onTap: page > 1 ? () => onPage(page - 1) : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(context.t('page_of', {'n': page, 'total': pages}), style: TextStyle(fontSize: 12.5, color: Palette.muted)),
          ),
          RoundButton(icon: Icons.chevron_right_rounded, label: context.t('next_page'), onTap: page < pages ? () => onPage(page + 1) : null),
        ],
      ),
    );
  }
}
