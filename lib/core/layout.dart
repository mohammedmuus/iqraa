import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Screen classes follow Material's window size classes, with an extra class for very small screens
/// such as flip phone cover screens and narrow split screen panes.
enum ScreenClass { small, compact, medium, expanded }

class Layout {
  Layout._();

  static const readable = 720.0;

  static ScreenClass classOf(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) {
      return ScreenClass.small;
    }
    if (width < 600) {
      return ScreenClass.compact;
    }
    if (width < 840) {
      return ScreenClass.medium;
    }
    return ScreenClass.expanded;
  }

  /// Side rail instead of the bottom bar on wide screens and on short landscape windows (phones turned sideways,
  /// split screen panes, open foldables), where a bottom bar would eat the little height there is.
  static bool useRail(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= 840 || (size.width > size.height && size.height < 500 && size.width >= 480);
  }

  /// Page padding that keeps content to a readable column in the middle of wide screens.
  static EdgeInsets page(BuildContext context, {double top = 0, double bottom = 0, double gutter = 12}) {
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(width < 360 ? 8.0 : gutter, (width - readable) / 2);
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }
}

/// Lays tiles out in as many columns as fit, at least [minTileWidth] wide each, up to [maxColumns].
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({super.key, required this.children, this.minTileWidth = 150, this.maxColumns = 4, this.spacing = 10, this.tileHeight});

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double spacing;
  final double? tileHeight;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final columns = ((box.maxWidth + spacing) / (minTileWidth + spacing)).floor().clamp(1, maxColumns);
        final width = (box.maxWidth - spacing * (columns - 1)) / columns;
        final height = tileHeight == null ? null : scaler.scale(tileHeight!);
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final child in children) SizedBox(width: width, height: height, child: child)],
        );
      },
    );
  }
}

/// Two widgets side by side, stacked when the space is too narrow for both.
class PairRow extends StatelessWidget {
  const PairRow({super.key, required this.first, required this.second, this.spacing = 10, this.stackBelow = 320});

  final Widget first;
  final Widget second;
  final double spacing;
  final double stackBelow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < stackBelow) {
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [first, SizedBox(height: spacing), second]);
        }
        return Row(children: [Expanded(child: first), SizedBox(width: spacing), Expanded(child: second)]);
      },
    );
  }
}
