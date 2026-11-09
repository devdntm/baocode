// The composer's mode pill (Agent, Ask, Plan) as Cursor draws it
// (`chat.look: cursor`, docs/fork.md): a soft round chip of the text's
// color, its icon and label bright, a small chevron; no border.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class CursorModePill extends StatelessWidget {
  const CursorModePill({
    super.key,
    required this.icon,
    required this.label,
    this.hovered = false,
    this.open = false,
  });

  final Widget Function(double size, Color color) icon;
  final String label;
  final bool hovered;
  final bool open;

  static const height = 24.0;

  /// The chip's fill: the text's color, fainter at rest than under the
  /// pointer or open.
  static double fill({required bool hovered, required bool open}) =>
      open ? 0.16 : (hovered ? 0.13 : 0.09);

  @override
  Widget build(BuildContext context) {
    final foreground = AppColors.textPrimary.withValues(alpha: 0.92);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: height,
      padding: const EdgeInsets.only(left: 8, right: 6),
      decoration: BoxDecoration(
        color: AppColors.text.withValues(
          alpha: fill(hovered: hovered, open: open),
        ),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon(14, foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 14,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}
