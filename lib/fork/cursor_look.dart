// The fork's `chat.look` setting (docs/fork.md): the conversation as
// Cursor draws it, its text, composer, commands and the auto mode prompt.
// Off by default; BaoCode Dev turns it on (tool/dev_app/build_dev_app.sh).
//
// The sizes are Cursor's own (its workbench CSS: `.rendered-markdown`,
// `--cursor-font-size-*`, `--cursor-spacing-*`), measured against its
// screenshots: the same SF Pro and Menlo, 14px text on 22.4px lines.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How a conversation looks: settings.json's `chat.look`.
enum ChatLook {
  /// BaoCode's (the default).
  baocode,

  /// Cursor's: its type sizes and letter spacing, a one-line composer,
  /// commands as cards and the auto mode prompt as "Run command".
  cursor;

  static const settingKey = 'chat.look';

  static ChatLook parse(Object? value) =>
      value == cursor.name ? cursor : baocode;

  /// How the conversations look now; main() keeps it to settings.json
  /// ([follow]).
  static final ValueNotifier<ChatLook> current = ValueNotifier(baocode);

  /// Whether they look as Cursor's now.
  static bool get isCursor => current.value == cursor;

  /// Sets [current] from [read] now and whenever [changes] notifies.
  static void follow(Listenable changes, Object? Function() read) {
    void update() => current.value = parse(read());
    update();
    changes.addListener(update);
  }
}

/// Cursor's type, as [ChatLook.cursor] draws the conversation.
abstract final class CursorType {
  /// What macOS's own text layout tightens SF Pro by and Flutter's does
  /// not (Core Text's tracking, about 0.003 em at 11 to 17 px): Cursor's
  /// lines, laid out by the system, come out that much narrower.
  static double tracking(double size) => -0.003 * size;

  /// [theme] with its text tracked as macOS tracks it ([tracking]), not
  /// Material 3's: its body text, which every [Material] and [Scaffold]
  /// gives the text in it, is spaced 0.25 px a letter, so BaoCode's read
  /// sparser than Cursor's in the same SF Pro.
  static ThemeData theme(ThemeData theme) {
    // The sizes come with the typography's geometry, which Theme.of merges
    // in under these styles.
    final sizes = theme.typography.englishLike;
    return theme.copyWith(
      textTheme: _tracked(theme.textTheme, sizes),
      primaryTextTheme: _tracked(theme.primaryTextTheme, sizes),
    );
  }

  static TextTheme _tracked(TextTheme theme, TextTheme sizes) {
    final sized = sizes.merge(theme);
    TextStyle? tracked(TextStyle? style, TextStyle? size) =>
        (style ?? const TextStyle()).copyWith(
          letterSpacing: tracking(size?.fontSize ?? textSize),
        );
    return theme.copyWith(
      displayLarge: tracked(theme.displayLarge, sized.displayLarge),
      displayMedium: tracked(theme.displayMedium, sized.displayMedium),
      displaySmall: tracked(theme.displaySmall, sized.displaySmall),
      headlineLarge: tracked(theme.headlineLarge, sized.headlineLarge),
      headlineMedium: tracked(theme.headlineMedium, sized.headlineMedium),
      headlineSmall: tracked(theme.headlineSmall, sized.headlineSmall),
      titleLarge: tracked(theme.titleLarge, sized.titleLarge),
      titleMedium: tracked(theme.titleMedium, sized.titleMedium),
      titleSmall: tracked(theme.titleSmall, sized.titleSmall),
      bodyLarge: tracked(theme.bodyLarge, sized.bodyLarge),
      bodyMedium: tracked(theme.bodyMedium, sized.bodyMedium),
      bodySmall: tracked(theme.bodySmall, sized.bodySmall),
      labelLarge: tracked(theme.labelLarge, sized.labelLarge),
      labelMedium: tracked(theme.labelMedium, sized.labelMedium),
      labelSmall: tracked(theme.labelSmall, sized.labelSmall),
    );
  }

  /// A message's text: 14px on 22.4px lines (`--cursor-font-size-lg`,
  /// `--cursor-line-height-lg`).
  static const textSize = 14.0;
  static const textHeight = 1.6;

  static TextStyle get text => TextStyle(
    color: AppColors.text,
    fontSize: textSize,
    height: textHeight,
    letterSpacing: tracking(textSize),
  );

  /// Inline code: Menlo at 12px (`--cursor-font-size-sm`), in the text's
  /// color on a pill of it at 8%, a line of its own height.
  static TextStyle get inlineCode =>
      AppFonts.uiCodeStyle(12)
          .copyWith(color: AppColors.text, height: 1.4, letterSpacing: 0);

  static Color get inlineCodeBackground =>
      AppColors.text.withValues(alpha: 0.08);

  static const inlineCodeRadius = Radius.circular(4);

  /// The space either side of inline code, in its text (0.3 em): a space
  /// at this size is that wide in a monospaced font.
  static TextStyle get inlineCodePad =>
      AppFonts.uiCodeStyle(12 * 0.3 / 0.6).copyWith(height: 1.4);

  /// Bold: medium (500), in the text's color.
  static const strong = TextStyle(fontWeight: FontWeight.w500);

  /// `h1` to `h6`: 17, 17, 14, 13 and the text's, semibold (590) on
  /// lines 1.5 high, in the primary text color.
  static const headingSizes = [17.0, 17.0, 14.0, 13.0, 14.0, 14.0];
  static const headingHeight = 1.5;

  /// Paragraphs and lists are 10 apart (`--cursor-spacing-2-5`); a heading
  /// has 16 before it and 4 after.
  static const gap = 10.0;
  static const headingGapBefore = 16.0;
  static const headingGapAfter = 4.0;

  /// A list's items are indented 28, their marker in the middle of that;
  /// 2 between them (`--cursor-spacing-0-5`).
  static const listIndent = 28.0;
  static const listItemGap = 2.0;
}
