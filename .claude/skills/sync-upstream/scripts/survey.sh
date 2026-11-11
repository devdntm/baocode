#!/bin/bash
# What a merge of upstream/main into main brings (docs/fork.md):
#
#   survey.sh            upstream's new commits; the files both the fork and
#                        upstream changed since the merge base, with the
#                        commits of each side on them
#   survey.sh --format   the fork's Dart that the project's formatter (Dart
#                        3.13, Flutter 3.47.5's) would change: files the fork
#                        added, and upstream files the fork touched that were
#                        formatted at the base and are not now
#
# DART=/path/to/dart overrides the formatter; FORK=<ref> looks at another
# state of the fork than main.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
dart="${DART:-$HOME/flutter-3.47.5/bin/dart}"
fork="${FORK:-main}"
base=$(git merge-base "$fork" upstream/main)

if [[ "${1:-}" == --format ]]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  formatted() { "$dart" format --output=none --set-exit-if-changed "$1" >/dev/null 2>&1; }
  echo "== fork-added files the formatter would change"
  changed=0
  while read -r file; do
    git show "$fork:$file" >"$tmp/added.dart"
    formatted "$tmp/added.dart" || { echo "$file"; changed=1; }
  done < <(git diff --name-only --diff-filter=A "$base" "$fork" -- '*.dart')
  [[ $changed == 1 ]] || echo "(none)"
  echo "== upstream files formatted at the base, not after the fork's edits"
  drifted=0
  while read -r file; do
    git show "$base:$file" >"$tmp/base.dart" 2>/dev/null || continue
    git show "$fork:$file" >"$tmp/now.dart"
    if formatted "$tmp/base.dart" && ! formatted "$tmp/now.dart"; then
      echo "$file"
      drifted=1
    fi
  done < <(git diff --name-only --diff-filter=M "$base" "$fork" -- '*.dart')
  [[ $drifted == 1 ]] || echo "(none)"
  exit 0
fi

echo "merge base: $(git log --oneline -1 "$base")"
echo
echo "== upstream commits not in $fork: $(git rev-list --count --no-merges "$fork"..upstream/main)"
git log --oneline --no-merges "$fork"..upstream/main
echo
echo "== files both sides changed since the base"
comm -12 \
  <(git diff --name-only "$base" "$fork" | sort) \
  <(git diff --name-only "$base" upstream/main | sort) |
  while read -r file; do
    echo "-- $file"
    git log --oneline --no-merges "$base..upstream/main" -- "$file" | sed 's/^/   upstream  /'
    git log --oneline --no-merges "$base..$fork" -- "$file" | sed 's/^/   fork      /'
  done
