import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../chat_session.dart';
import '../composer/session_model_picker.dart';
import '../panels/interaction_panel.dart' show PanelButton;
// fork: Build as Cursor's plans have it (docs/fork.md).
import '../../plan/plan_build.dart';
import '../../plan/plan_view.dart' show PlanPreview;

/// The conversation whose plan its cards start (see [PlanStartBar]): the
/// chat's, over its history.
class PlanStartScope extends InheritedWidget {
  const PlanStartScope({
    super.key,
    required this.session,
    required super.child,
  });

  final ChatSession session;

  static ChatSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlanStartScope>()?.session;

  @override
  bool updateShouldNotify(PlanStartScope oldWidget) =>
      session != oldWidget.session;
}

/// Starts [session]'s plan awaiting (see [ChatSession.startPlan]), with
/// the model picked beside the button. Nothing while none awaits, nor,
/// [path] given, while the one awaiting is in another file.
class PlanStartBar extends StatelessWidget {
  const PlanStartBar({
    super.key,
    required this.session,
    this.path,
    this.padding = EdgeInsets.zero,
    this.maxPickerWidth,
  });

  final ChatSession session;
  final String? path;

  /// Around it, where it shows.
  final EdgeInsets padding;

  /// The model picker cut short past this, the bar as wide as it needs,
  /// for a row of others (the plan's file bar); else it takes the width
  /// it is given.
  final double? maxPickerWidth;

  @override
  Widget build(BuildContext context) {
    // fork: a plan's file: Build its open to-dos, before and after it is
    // started; on its card in the history only while it awaits.
    if (path case final path? when PlanPreview.isPlan(path)) {
      return PlanBuildBar(
        path: path,
        session: session,
        always: maxPickerWidth != null,
        padding: padding,
        maxPickerWidth: maxPickerWidth ?? 220,
      );
    }
    return _upstream(context);
  }

  Widget _upstream(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final plan = session.awaitingPlan;
      if (plan == null || (path != null && plan.path != path)) {
        return const SizedBox.shrink();
      }
      final l10n = context.l10n;
      final picker = SessionModelPicker(session: session);
      final bar = Row(
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: maxPickerWidth == null
            ? MainAxisSize.max
            : MainAxisSize.min,
        children: [
          if (maxPickerWidth case final width?)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: picker,
            )
          else
            Flexible(child: picker),
          const SizedBox(width: 6),
          PanelButton(
            label: l10n.planStart,
            tooltip: l10n.planStartHint,
            primary: true,
            // Not while the turn that put it is still under way.
            onTap: session.canStartPlan
                ? () => session.startPlan(l10n.planStartMessage)
                : null,
          ),
        ],
      );
      return Padding(padding: padding, child: bar);
    },
  );
}
