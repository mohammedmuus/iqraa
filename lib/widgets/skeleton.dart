import 'package:flutter/material.dart';

import '../theme.dart';

/// Grey placeholders that gently pulse while content loads, laid out like the content on its way.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(opacity: Tween(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)), child: widget.child),
    );
  }
}

/// One placeholder bar.
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius = 6, this.color});

  final double? width;
  final double height;
  final double radius;

  /// Stone grey unless given.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(width: width, height: height, decoration: BoxDecoration(color: color ?? Palette.stone, borderRadius: BorderRadius.circular(radius)));
  }
}

/// Lines of text on their way, such as a chapter or a description.
class SkeletonText extends StatelessWidget {
  const SkeletonText({super.key, this.blocks = 4, this.arabic = true, this.color});

  final int blocks;
  final bool arabic;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        crossAxisAlignment: arabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < blocks; i++) ...[
            FractionallySizedBox(widthFactor: 1, child: Bone(height: 16, color: color)),
            const SizedBox(height: 10),
            FractionallySizedBox(widthFactor: i.isEven ? 0.86 : 0.7, child: Bone(height: 16, color: color)),
            const SizedBox(height: 10),
            FractionallySizedBox(widthFactor: i.isEven ? 0.6 : 0.78, child: Bone(color: color)),
            const SizedBox(height: 26),
          ],
        ],
      ),
    );
  }
}

/// Rows of a list on their way, such as a book's chapters.
class SkeletonRows extends StatelessWidget {
  const SkeletonRows({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(22)),
        child: Column(
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    const Bone(width: 30, height: 30, radius: 15),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.55, child: const Bone(height: 13)),
                          const SizedBox(height: 7),
                          const FractionallySizedBox(widthFactor: 0.3, child: Bone(height: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Book covers on their way, two to a row.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.rows = 2});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++) ...[
            const Row(
              children: [
                Expanded(child: Bone(height: 210, radius: 18)),
                SizedBox(width: 8),
                Expanded(child: Bone(height: 210, radius: 18)),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
