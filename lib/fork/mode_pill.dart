// The composer's mode pill (Agent, Ask, Plan) as Cursor draws it
// (`chat.look: cursor`, docs/fork.md), measured on its screenshot: 20
// high and round, a fill of the bright text's color at 6%, the label at
// 65% in 12px, the icon and the chevron at 43%; Agent's infinity a thin
// stroke, as Cursor's.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/codicons.dart';

class CursorModePill extends StatelessWidget {
  const CursorModePill({
    super.key,
    required this.icon,
    required this.label,
    this.iconData,
    this.hovered = false,
    this.open = false,
  });

  /// The option's own icon, where [iconData] is not Agent's infinity.
  final Widget Function(double size, Color color) icon;
  final IconData? iconData;
  final String label;
  final bool hovered;
  final bool open;

  static const height = 20.0;

  /// The chip's fill: the bright text's color, fainter at rest than under
  /// the pointer or open.
  static double fill({required bool hovered, required bool open}) =>
      open ? 0.12 : (hovered ? 0.09 : 0.06);

  @override
  Widget build(BuildContext context) {
    final bright = AppColors.textPrimary;
    final label = bright.withValues(alpha: hovered || open ? 0.8 : 0.65);
    final faint = bright.withValues(alpha: 0.43);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: height,
      padding: const EdgeInsets.only(left: 8, right: 7),
      decoration: BoxDecoration(
        color: bright.withValues(
          alpha: fill(hovered: hovered, open: open),
        ),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconData == Icons.all_inclusive_rounded)
            CustomPaint(size: const Size(14, 14), painter: _Infinity(faint))
          else
            icon(13, faint),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              this.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: label,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Icon(Codicons.chevronDown, size: 11, color: faint),
        ],
      ),
    );
  }
}

/// ∞ as a thin stroke: a lemniscate as wide as its box, half as high.
class _Infinity extends CustomPainter {
  const _Infinity(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final a = size.width / 2 - 0.8;
    final center = size.center(Offset.zero);
    final path = Path();
    for (var i = 0; i <= 96; i++) {
      final t = i / 96 * 2 * math.pi;
      final d = 1 + math.sin(t) * math.sin(t);
      final point =
          center +
          Offset(a * math.cos(t) / d, a * math.sin(t) * math.cos(t) / d);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_Infinity old) => old.color != color;
}
