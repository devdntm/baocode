// A to-do's status as Cursor draws it (docs/fork.md): thin outlines in the
// faint text's color, as its cancelled one (a slashed circle) is; a
// pending one a circle, one in progress a dashed circle, a done one a
// circle with a check. The to-do's row and its status menu alike.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import 'plan_todos.dart';

abstract final class TodoStatusIcons {
  static const size = 15.0;

  static Widget pending([Color? color]) =>
      Icon(Codicons.circleLargeOutline, size: size, color: color ?? _faint);

  static Widget inProgress([Color? color]) => CustomPaint(
    size: const Size.square(size),
    painter: _DashedCircle(color ?? _faint),
  );

  static Widget completed([Color? color]) =>
      Icon(Codicons.pass, size: size, color: color ?? _faint);

  static Widget cancelled([Color? color]) =>
      Icon(Codicons.circleSlash, size: size, color: color ?? _faint);

  /// The menu's for [state].
  static Widget of(PlanTodoState state) => switch (state) {
    PlanTodoState.pending => pending(),
    PlanTodoState.inProgress => inProgress(),
    PlanTodoState.completed => completed(),
    PlanTodoState.cancelled => cancelled(),
  };

  static Color get _faint => AppColors.textFaint;
}

/// A circle of dashes, as codicons' circles are drawn: inside a 16 box at
/// 15, a stroke of about one pixel.
class _DashedCircle extends CustomPainter {
  const _DashedCircle(this.color);

  final Color color;

  static const dashes = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width / 13;
    final radius = size.width / 2 - stroke * 1.4;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    const step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * step - math.pi / 2 + step * 0.18,
        step * 0.5,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}
