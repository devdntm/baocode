// The fork's `chat.look` setting (docs/fork.md): the conversation as
// Cursor draws it, its text, composer, commands and the auto mode prompt.
// Off by default; BaoCode Dev turns it on (tool/dev_app/build_dev_app.sh).
//
// The sizes are Cursor's own (its workbench CSS: `.rendered-markdown`,
// `--cursor-font-size-*`, `--cursor-spacing-*`), measured against its
// screenshots: the same SF Pro and Menlo, 14px text on 22.4px lines.

import 'package:bao_markdown/bao_markdown.dart';
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

  /// Bold: semibold, in the text's color. Cursor's CSS says 500, but drawn
  /// by Chromium with macOS's font smoothing it reads as 600 does here.
  static const strong = TextStyle(fontWeight: FontWeight.w600);

  /// `h1` to `h6`: 17, 17, 14, 13 and the text's, semibold (590) on
  /// lines 1.5 high, in the primary text color.
  static const headingSizes = [17.0, 17.0, 14.0, 13.0, 14.0, 14.0];
  static const headingHeight = 1.5;

  /// Paragraphs and lists are 10 apart (`--cursor-spacing-2-5`); a heading
  /// has 16 before it and 4 after.
  static const gap = 10.0;
  static const headingGapBefore = 16.0;
  static const headingGapAfter = 4.0;

  /// [style], a markdown editor's (the IDE's preview, a plan's, a
  /// stash's), as the chat's text under Cursor's look: the same size, line
  /// and tracking, headings, bold and inline code; an empty line between
  /// paragraphs [gap] high, as the chat's paragraphs are apart. As it is
  /// under BaoCode's.
  static MarkdownEditorStyle markdown(MarkdownEditorStyle style) {
    if (!ChatLook.isCursor) return style;
    // As Cursor's preview, measured on it: headings bigger than the chat's
    // (20 for `##`), semibold on tight lines; bold semibold too.
    const heading = TextStyle(fontWeight: FontWeight.w600, height: 1.25);
    return style.copyWith(
      text: style.text.merge(
        TextStyle(
          fontSize: textSize,
          height: textHeight,
          letterSpacing: tracking(textSize),
        ),
      ),
      headings: [
        for (final size in markdownHeadingSizes)
          // In the text's color, as Cursor's.
          heading.copyWith(
            fontSize: size,
            color: AppColors.text,
            letterSpacing: tracking(size),
          ),
      ],
      // With the empty line before it, 16 over a heading; after it, the
      // empty line alone.
      headingSpacing: const [(6, 0), (6, 0), (6, 0), (6, 0), (6, 0)],
      // No line under the big headings, as Cursor's (none to set back).
      headingRule: const Color(0x00000000),
      bold: strong,
      code: inlineCode,
      codeBackground: inlineCodeBackground,
      blank: const TextStyle(fontSize: textSize, height: gap / textSize),
      // As Cursor's: 0.3 em either side of inline code on its pill.
      codePadding: 12 * 0.3,
      // Its lists: a disc of the text's size, the text 20 in, each level
      // 20 further; 10 over and under a list, 2 between items.
      bullet: bullet,
      bulletWidth: 20,
      listIndent: 20,
      listGap: gap,
      itemGap: listItemGap,
      // Its code blocks: a faint fill of the text's color, no edge.
      codeBlockBackground: AppColors.text.withValues(alpha: 0.08),
      codeBlockBorder: const Color(0x00000000),
      codeBlockRadius: 6,
      codeBlockPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      // Its tables: as wide as the page, the head unfilled, lines faint.
      fitTables: true,
      table: MdTableStyle(
        border: AppColors.text.withValues(alpha: 0.12),
        head: const Color(0x00000000),
        accent: style.tableStyle.accent,
        control: style.tableStyle.control,
        surface: style.tableStyle.surface,
        shadow: style.tableStyle.shadow,
        radius: 10,
      ),
    );
  }

  /// A markdown preview's `h1` to `h6` (Cursor's preview: bigger than the
  /// chat's).
  static const markdownHeadingSizes = [24.0, 20.0, 16.0, 14.0, 14.0, 14.0];

  /// A bullet's: a disc bigger than the text's `•`, its line as tall.
  static const bullet = TextStyle(
    fontSize: 17,
    height: textSize * textHeight / 17,
  );

  /// A list's items are indented 28, their marker in the middle of that;
  /// 2 between them (`--cursor-spacing-0-5`).
  static const listIndent = 28.0;
  static const listItemGap = 2.0;
}
