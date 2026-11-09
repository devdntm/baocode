// A markdown table as Cursor's conversation lays it out (`chat.look:
// cursor`, docs/fork.md): as wide as the conversation, its columns sharing
// that by what is in them, their text wrapping, as an HTML table's
// automatic layout does, words too long broken as Cursor's are.

import 'dart:math' as math;

import 'package:flutter/painting.dart';

abstract final class CursorTable {
  /// Room in a cell about its text: 10 each side, 6 over and under.
  static const cellPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

  static const radius = 10.0;

  /// The widths of the columns of a table [width] wide whose cells hold
  /// [cells] (rows of their text, the head's in [headStyle]), each with
  /// [cellPadding] about it; null only where [width] is not known (the
  /// table then scrolls at its columns' own widths).
  ///
  /// As a browser's automatic layout: each column's least width is its
  /// longest word's, its most its longest line's. Where all fit at their
  /// most, they grow to [width] in proportion to that; else each has its
  /// least and a share of the rest in proportion to what it wants more.
  static List<double>? widths(
    List<List<String>> cells, {
    required TextStyle style,
    required TextStyle headStyle,
    required double width,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (cells.isEmpty || !width.isFinite) return null;
    final columns = cells.map((row) => row.length).reduce(math.max);
    if (columns == 0) return null;
    final pad = cellPadding.horizontal;
    final least = List<double>.filled(columns, pad);
    final most = List<double>.filled(columns, pad);
    for (final (r, row) in cells.indexed) {
      final textStyle = r == 0 ? headStyle : style;
      for (final (c, text) in row.indexed) {
        most[c] = math.max(most[c], _width(text, textStyle, textScaler) + pad);
        for (final word in text.split(RegExp(r'\s+'))) {
          if (word.isEmpty) continue;
          least[c] = math.max(
            least[c],
            _width(word, textStyle, textScaler) + pad,
          );
        }
      }
    }
    final sumLeast = least.fold(0.0, (a, b) => a + b);
    final sumMost = most.fold(0.0, (a, b) => a + b);
    if (sumMost <= width) {
      return [for (final m in most) m * width / sumMost];
    }
    // Its words alone wider still: as their share, words broken where they
    // must be, as Cursor's are; the table never wider than the chat.
    if (sumLeast >= width) {
      return [for (final l in least) l * width / sumLeast];
    }
    final want = sumMost - sumLeast;
    final room = width - sumLeast;
    return [
      for (var c = 0; c < columns; c++)
        least[c] + (want == 0 ? 0 : room * (most[c] - least[c]) / want),
    ];
  }

  static double _width(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    // A pixel's room for rounding: a word that just fits is not broken.
    return width.ceilToDouble() + 1;
  }
}
