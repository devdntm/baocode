---
name: sync-upstream
description: Merge upstream baocode-dev/baocode into this fork (devdntm/baocode) without losing the fork's features or keeping duplicates of upstream's. Use when the user asks to sync, update or merge the fork with upstream / the main baocode repo, to pull in new upstream releases, or when `git log main..upstream/main` is not empty and they want it in.
---

# Sync the fork with upstream

The fork's rules are in `docs/fork.md` (read its "Remote и обновление", "Правила кода" and the `// fork:` table first). Upstream must merge in cleanly; the fork's edits to upstream files are small and marked `// fork:`. A merge goes wrong in two ways: a conflict resolved so a fork feature silently disappears, and a feature both sides built kept twice. This skill guards against both.

Work in a separate worktree, then fast-forward `main`: other sessions use the main working copy, and it must never sit on a half-done merge. Commit to `main`, no other branch; push only when the user asks.

## 1. Look before merging

```sh
git fetch upstream --tags
.claude/skills/sync-upstream/scripts/survey.sh          # what comes, what both sides touched
```

`survey.sh` prints upstream's new commits, the files both the fork and upstream changed since the merge base, and the upstream commits touching each. Read every upstream commit whose subject sounds like a fork feature (the fork's features: Cursor layout and look, plans and to-dos, checkpoints, claude-context index, Cursor import, project switcher, browser page, trackpad momentum, command cards, context meter). Read its message and diff (`git show <sha>`), not only the subject: duplicates hide in commits like "feat(chat): …" that do what the fork already does.

## 2. Formatting first

The project's Dart is Flutter 3.47.5's (`~/flutter-3.47.5/bin/dart`, Dart 3.13); `dart` on PATH is older (3.8) and lays code out differently. A file formatted with the wrong one differs from upstream in every reformatted line, and each such line can conflict. CI checks the format of changed files with 3.13.

Before merging, check the fork's own changes:

```sh
.claude/skills/sync-upstream/scripts/survey.sh --format
```

It lists fork-added files 3.13 would change, and upstream files the fork touched that were 3.13-clean at the merge base but no longer are. Format those with `~/flutter-3.47.5/bin/dart format <files>` (only those: never a whole upstream file that upstream itself left unformatted), check that an upstream file now differs from the base only by the fork's own lines (`git diff --numstat <base> -- <file>`: additions only, no reformat churn), and commit that separately ("style(fork): …") before the merge.

## 3. Trial merge in a worktree

```sh
git worktree add --detach ../baocode-merge-check main
cd ../baocode-merge-check
git merge --no-commit --no-ff upstream/main
```

For each conflict, decide by what each side means, not by which is shorter:

- **Same feature on both sides** (a duplicate): take upstream's when it covers the fork's (it usually is fuller: merges, settings, phone/link support, tests). Delete the fork's version entirely: its code, now-unused helpers, its test, its strings in `lib/fork/fork_strings.dart`, its row in docs/fork.md's table. Keep whatever part of the fork's feature upstream does not have, and say in docs/fork.md which part is now upstream's.
- **Upstream restructured code the fork touched** (moved, re-indented, wrapped): take upstream's file and re-apply the fork's edit in its new place, with its `// fork:` comment. Compare the fork's edits before and after (`git diff <base> main -- <file>` against `git diff upstream/main -- <file>`): the same edits, nothing more.
- **Only formatting differs**: upstream's.

`scripts/take-side.py <file> ours|theirs` resolves every conflict block of a file to one side, for when that is right for all of them; then re-apply what must stay. `git checkout --theirs <file>` takes upstream's whole file: only after checking `git log <base>..main -- <file>` that the fork has nothing else in it.

Also look at the files merged without conflicts that both sides touched (survey's list): they can still clash in meaning (a fork call into code upstream changed, two prompts for the same action).

## 4. Check it

In the worktree (it has no build outputs: copy the prebuilt Rust library and get packages; `packages/bao_iroh` unchanged since the release, see docs/fork.md):

```sh
mkdir -p packages/bao_iroh/build/prebuilt
cp -R ../baocode/packages/bao_iroh/build/prebuilt/. packages/bao_iroh/build/prebuilt/
~/flutter-3.47.5/bin/flutter pub get
~/flutter-3.47.5/bin/flutter analyze                      # must be clean: unused imports left by a dropped duplicate show here
```

Tests: not the whole suite (slow, see CLAUDE.md). Run the fork's (`test/fork test/plan test/ide/cursor_layout test/integrations`), the tests of the shared files and features (`test/kernel_test.dart test/transcript_test.dart test/sidebar_test.dart test/sidebar test/composer_test.dart …`), and upstream's changed tests (`git diff --name-only <base> upstream/main -- test | grep _test.dart`). Run them in the background and wait for the result.

A failure is the merge's only if it passes on both sides alone. Check it on pure upstream in a second worktree (`git worktree add --detach ../baocode-upstream-check upstream/main`, same setup) and on `main`. Known failures on both as of 1.9.4: `transcript_test.dart` "a turn done is timed on its message" (time zone), and `composer_test.dart` "an edit stays open while another conversation is visited" (upstream's semantics tree check).

Format check as CI does, on what differs from upstream:

```sh
git diff --cached --name-only upstream/main -- '*.dart' | xargs ~/flutter-3.47.5/bin/dart format --output=none --set-exit-if-changed
```

A file listed there that is upstream's own unformatted code (check `git show upstream/main:<file>` the same way) is left as it is.

## 5. Land it

1. Update `docs/fork.md`: rows of the `// fork:` table for edits that moved or went away, notes on features now upstream's.
2. Commit the merge in the worktree; the message lists each conflict and duplicate and how it was resolved.
3. In the main working copy: `git status` clean, `main` not moved since the trial began (else merge again), then `git merge --ff-only <merge sha>`.
4. `git worktree remove --force ../baocode-merge-check` (and the upstream one), delete temp files.
5. `~/flutter-3.47.5/bin/flutter build macos --release` in the main copy: it must build.
6. Tell the user what came in, each duplicate and conflict and what was kept, test results with the failures that are upstream's own, and that BaoCode Dev needs rebuilding (`tool/dev_app/build_dev_app.sh`; from a session running inside Dev, install from a detached process, as Dev's quitting ends the session). Do not push unless asked.
