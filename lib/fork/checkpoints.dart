// Checkpoints as Cursor has them (`chat.look: cursor`, docs/fork.md): a
// message of the user's puts the files back as they were before it was
// sent ("Restore checkpoint"), the conversation after it dimmed, and
// dropped as the next message is sent; a message edited and sent again
// may put them back too. Claude Code keeps the files
// (`CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING`) and puts them back
// (`rewind_files`): what its tools edited, not what commands wrote.

import 'package:flutter/material.dart';

import '../chat/widgets/hover_builder.dart';
import '../ide/ide_hover.dart';
import '../theme/app_theme.dart';
import '../theme/codicons.dart';
import 'cursor_look.dart';

/// A conversation whose files go back to a message of the user's.
abstract interface class RestoresCheckpoints {
  /// Whether the user's message at [index] has a checkpoint: files the
  /// agent changed from it on, which can be put back.
  bool canRestoreAt(int index);

  /// Puts the files back as they were before the message at [index]; the
  /// conversation from it on is dropped as the next message is sent.
  void restoreCheckpoint(int index);

  /// Puts the files back as before the message at [index], the
  /// conversation left as it is (a message edited, sent again from there).
  void revertFilesFrom(int index);

  /// The message the files were put back to: it and what follows show
  /// dimmed till the next message, which goes on from before it.
  int? get restoredAt;

  /// The conversation as it was, the files as they are now.
  void cancelRestore();
}

/// How dim what a restore is to drop shows.
const restoredDimming = 0.45;

/// Over a message of the user's, in its bottom right corner while the
/// pointer is over it: Cursor's restore arrow, "Restore checkpoint" on
/// hover; asked first.
class CheckpointHover extends StatelessWidget {
  const CheckpointHover({
    super.key,
    required this.child,
    required this.onRestore,
  });

  final Widget child;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final restore = onRestore;
    if (restore == null || !ChatLook.isCursor) return child;
    return HoverBuilder(
      builder: (context, hovered) => Stack(
        children: [
          child,
          Positioned(
            right: 10,
            bottom: 8,
            child: Visibility.maintain(
              visible: hovered,
              child: _RestoreButton(
                onTap: () async {
                  if (await confirmRestore(context)) restore();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Asks whether to put the files back.
  static Future<bool> confirmRestore(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore checkpoint?'),
          content: const Text(
            'The files the agent changed from this message on go back to '
            'how they were before it. The conversation after it is dropped '
            'when you send your next message. What commands wrote is not '
            'put back.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      ) ??
      false;
}

/// The arrow back, as Cursor's: faint, brighter on a light ground under
/// the pointer.
class _RestoreButton extends StatelessWidget {
  const _RestoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IdeHover(
    message: 'Restore checkpoint',
    child: Semantics(
      button: true,
      label: 'Restore checkpoint',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : null,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              Codicons.discard,
              size: 15,
              color: hovered ? AppColors.text : AppColors.textMuted,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Under the message the files were put back to: what the next message
/// does, and a way back.
class RestoredNote extends StatelessWidget {
  const RestoredNote({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            'Checkpoint restored: your next message goes on from here.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(width: 8),
        HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: onCancel,
            child: Text(
              'Keep the conversation',
              style: TextStyle(
                fontSize: 12,
                color: hovered ? AppColors.text : AppColors.accent,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Sent again from an older message whose files changed after it: put
/// them back first, or not, or neither (null).
Future<bool?> askRevertOnResend(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Submit from a previous message?'),
    content: const Text(
      'The agent changed files after this message. Put them back as they '
      'were before it, or keep them as they are now.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Continue without reverting'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Revert and submit'),
      ),
    ],
  ),
);
