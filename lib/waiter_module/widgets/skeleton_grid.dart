import 'package:flutter/material.dart';

import '../../services/app_themes.dart';
import '../theme/waiter_design.dart';

/// Shimmering skeleton grid shown while the tables list is fetching.
/// Feels snappier than a centered spinner because the layout is already
/// in place the moment real data arrives.
class SkeletonTablesGrid extends StatefulWidget {
  final int cells;

  const SkeletonTablesGrid({super.key, this.cells = 8});

  @override
  State<SkeletonTablesGrid> createState() => _SkeletonTablesGridState();
}

class _SkeletonTablesGridState extends State<SkeletonTablesGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final w = constraints.maxWidth;
      final maxExtent = w < 420 ? w : 220.0;
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(WaiterSpacing.md),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          mainAxisSpacing: WaiterSpacing.sm + 2,
          crossAxisSpacing: WaiterSpacing.sm + 2,
          childAspectRatio: 1.35,
        ),
        itemCount: widget.cells,
        itemBuilder: (_, __) => _SkeletonCard(pulse: _ctrl),
      );
    });
  }
}

class _SkeletonCard extends StatelessWidget {
  final Animation<double> pulse;
  const _SkeletonCard({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final t = pulse.value;
        final base = context.appCardBg;
        final highlight = context.appSurfaceAlt;
        return Container(
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, t),
            borderRadius: BorderRadius.circular(WaiterRadius.md + 2),
            border: Border.all(
              color: context.appBorder.withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.all(WaiterSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bar(context, width: 88, height: 12, t: t),
              _bar(context, width: 56, height: 10, t: t),
              _bar(context, width: 72, height: 10, t: t),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(
    BuildContext context, {
    required double width,
    required double height,
    required double t,
  }) {
    final base = context.appSurfaceAlt;
    final highlight = context.appBorder;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color.lerp(base, highlight, t),
        borderRadius: BorderRadius.circular(WaiterRadius.sm),
      ),
    );
  }
}
