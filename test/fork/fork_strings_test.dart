import 'package:baocode/fork/fork_strings.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fork's strings follow the app's locale, English where it has none.
void main() {
  test('the locale names the language', () {
    expect(ForkStrings.forLocale('zh_CN').chinese, isTrue);
    expect(ForkStrings.forLocale('zh').chinese, isTrue);
    expect(ForkStrings.forLocale('en').chinese, isFalse);
    expect(ForkStrings.forLocale(null).chinese, isFalse);
  });

  Future<String> layoutTitle(WidgetTester tester, Locale? locale) async {
    late String title;
    final probe = Builder(
      builder: (context) {
        title = context.fork.ideLayoutTitle;
        return const SizedBox();
      },
    );
    await tester.pumpWidget(
      locale == null
          ? probe
          : Localizations(
              locale: locale,
              delegates: const [
                AppLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              child: probe,
            ),
    );
    return title;
  }

  testWidgets('context.fork reads the locale in scope', (tester) async {
    expect(await layoutTitle(tester, const Locale('zh', 'CN')), 'IDE 布局');
    expect(await layoutTitle(tester, const Locale('en')), 'IDE layout');
    expect(await layoutTitle(tester, null), 'IDE layout');
  });
}
