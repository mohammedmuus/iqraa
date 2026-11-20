import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class TabItem {
  const TabItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The bar dips into a curved notch under the active tab. A green disc rides in the notch and, on a new tab,
/// sinks into the bar, slides across and rises again while the notch stretches to follow it.
class BottomBar extends StatefulWidget {
  const BottomBar({super.key, required this.items, required this.index, required this.onTap});

  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  State<BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<BottomBar> with SingleTickerProviderStateMixin {
  static const _barHeight = 66.0;
  static const _disc = 50.0;
  static const _lift = 24.0;

  late final AnimationController _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  late int _from = widget.index;

  @override
  void didUpdateWidget(covariant BottomBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = old.index;
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  void _tap(int i) {
    HapticFeedback.selectionClick();
    widget.onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = media.padding.bottom;
    return MediaQuery(
      data: media.copyWith(textScaler: media.textScaler.clamp(maxScaleFactor: 1.15)),
      child: SizedBox(
        height: _barHeight + bottom,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / widget.items.length;
            double centre(int i) => slot * i + slot / 2;
            return AnimatedBuilder(
              animation: _motion,
              builder: (context, _) {
                final t = _motion.value;
                final glide = Curves.easeInOutCubic.transform(t);
                final x = _motion.isDismissed ? centre(widget.index) : centre(_from) + (centre(widget.index) - centre(_from)) * glide;
                final wave = math.sin(t * math.pi);
                final sink = wave * 14;
                final stretch = wave * 18;
                final settle = Curves.elasticOut.transform(t);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _NotchPainter(centre: x, stretch: stretch, depth: 30 - sink * 0.6)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: _barHeight,
                      child: Row(
                        children: [
                          for (var i = 0; i < widget.items.length; i++)
                            Expanded(
                              child: _Slot(item: widget.items[i], active: i == widget.index, onTap: () => _tap(i)),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: x - _disc / 2,
                      top: -_lift + sink,
                      width: _disc,
                      height: _disc,
                      child: IgnorePointer(
                        child: Transform.scale(
                          scale: 0.86 + 0.14 * (_motion.isDismissed ? 1 : settle),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Palette.green,
                              shape: BoxShape.circle,
                              boxShadow: [const BoxShadow(color: Color(0x331F6B4A), blurRadius: 16, offset: Offset(0, 8))],
                            ),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                transitionBuilder: (child, animation) => ScaleTransition(
                                  scale: animation,
                                  child: RotationTransition(turns: Tween<double>(begin: -0.12, end: 0).animate(animation), child: child),
                                ),
                                child: Icon(widget.items[widget.index].icon, key: ValueKey(widget.index), color: Colors.white, size: 23),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.item, required this.active, required this.onTap});

  final TabItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        highlightColor: Colors.transparent,
        splashColor: Palette.stone,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: const Alignment(0, -0.32),
              child: AnimatedOpacity(
                opacity: active ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: AnimatedSlide(
                  offset: active ? const Offset(0, -0.8) : Offset.zero,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: Icon(item.icon, size: 22, color: Palette.muted),
                ),
              ),
            ),
            Positioned(
              left: 2,
              right: 2,
              bottom: 9,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                style: TextStyle(
                  color: active ? Palette.ink : Palette.muted,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  height: 1.1,
                ),
                // A longer label, such as Dhikr & Groups, shrinks a little to fit rather than being cut short.
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(item.label, textAlign: TextAlign.center, maxLines: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White bar with a smooth notch cut down into its top edge at [centre].
class _NotchPainter extends CustomPainter {
  const _NotchPainter({required this.centre, required this.stretch, required this.depth});

  final double centre;
  final double stretch;
  final double depth;

  @override
  void paint(Canvas canvas, Size size) {
    final half = 40.0 + stretch;
    const shoulder = 16.0;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(centre - half - shoulder, 0)
      ..cubicTo(centre - half, 0, centre - half + 6, depth, centre, depth)
      ..cubicTo(centre + half - 6, depth, centre + half, 0, centre + half + shoulder, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawShadow(path, const Color(0x140B0B0C), 4, false);
    canvas.drawPath(path, Paint()..color = Palette.surface);
  }

  @override
  bool shouldRepaint(_NotchPainter old) => old.centre != centre || old.stretch != stretch || old.depth != depth;
}

/// Navigation for wide and short landscape windows. Same tabs and colours as the bottom bar.
class SideRail extends StatelessWidget {
  const SideRail({super.key, required this.items, required this.index, required this.onTap});

  final List<TabItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final short = MediaQuery.sizeOf(context).height < 420;
    return Container(
      width: short ? 76 : 92,
      decoration: BoxDecoration(color: Palette.surface, border: Border(right: BorderSide(color: Palette.line))),
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: short ? 6 : 16),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++)
              Semantics(
                selected: i == index,
                button: true,
                label: items[i].label,
                excludeSemantics: true,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: short ? 5 : 9),
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutBack,
                          width: i == index ? 52 : 40,
                          height: short ? 32 : 36,
                          decoration: BoxDecoration(color: i == index ? Palette.green : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                          child: Icon(items[i].icon, size: 21, color: i == index ? Colors.white : Palette.muted),
                        ),
                        if (!short) ...[
                          const SizedBox(height: 4),
                          Text(
                            items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: i == index ? Palette.ink : Palette.muted, fontWeight: i == index ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
