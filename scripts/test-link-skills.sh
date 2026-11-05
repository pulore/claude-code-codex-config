#!/usr/bin/env bash
# Runs scripts/link-skills.sh in throwaway git repos and checks what it
# leaves behind. A skill that differs between .claude/skills and
# .agents/skills stops it before anything changes. Identical and one-sided
# skills move across, and a second run changes nothing. .claude/skills is
# kept whenever a skill doesn't read the same through the new link.
set -euo pipefail
cd "$(dirname "$0")/.."

script="$PWD/scripts/link-skills.sh"
tmp="$(mktemp -d)"
trap 'cd /; rm -rf "$tmp"' EXIT
failures=0

# Keep the user's git config and global gitignore out of the test repos.
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"

# Creates an empty git repo under $tmp and changes into it.
repo() {
  git -c init.defaultBranch=main init -q "$tmp/$1"
  cd "$tmp/$1"
}

# Writes DIR/NAME/SKILL.md with TEXT as its description.
skill() {
  mkdir -p "$1/$2"
  printf -- '---\nname: %s\ndescription: %s\n---\n' "$2" "$3" >"$1/$2/SKILL.md"
}

# Every path in the work tree with its link target or checksum, then the
# git index. Two equal snapshots mean nothing changed.
snapshot() {
  find . -path ./.git -prune -o -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then
      echo "link $p -> $(readlink "$p")"
    elif [ -d "$p" ]; then
      echo "dir  $p"
    else
      echo "file $p $(cksum <"$p")"
    fi
  done
  git ls-files -s
}

# Runs link-skills.sh in the current repo, keeping its exit status in
# $status and its error output in $tmp/err.
run() {
  status=0
  "$script" >"$tmp/out" 2>"$tmp/err" || status=$?
}

# True if .claude/skills is the link to ../.agents/skills and git has it
# staged as a symlink.
linked() {
  [ -L .claude/skills ] &&
    [ "$(readlink .claude/skills)" = ../.agents/skills ] &&
    [ "$(git ls-files -s .claude/skills | cut -d' ' -f1)" = 120000 ]
}

result() {
  if [ "$1" = pass ]; then
    printf 'ok    %s\n' "$2"
  else
    printf 'FAIL  %s (exit %s)\n' "$2" "$status"
    sed 's/^/      /' "$tmp/err"
    failures=$((failures + 1))
  fi
}

# Conflict: two skills differ, one is identical, one is only in .claude.
repo conflict
skill .claude/skills deploy "Run make deploy-staging first."
skill .agents/skills deploy "Never deploy on a Friday."
skill .claude/skills lint "Run npm run lint."
skill .agents/skills lint "Run npm run lint -- --fix."
skill .claude/skills review "Review the diff."
skill .agents/skills review "Review the diff."
skill .claude/skills notes "Only in .claude/skills."
before=$(snapshot)
run
if [ "$status" -eq 1 ] && [ "$(snapshot)" = "$before" ] && [ ! -L .claude/skills ] &&
  grep -qx '  deploy' "$tmp/err" && grep -qx '  lint' "$tmp/err" &&
  ! grep -qx '  review' "$tmp/err" && ! grep -qx '  notes' "$tmp/err"; then
  result pass "conflict: lists deploy and lint, exits 1 and changes nothing"
else
  result fail "conflict: lists deploy and lint, exits 1 and changes nothing"
fi

# Identical overlap: the same skill in both folders.
repo identical
skill .claude/skills review "Review the diff."
skill .agents/skills review "Review the diff."
cp -R .agents/skills "$tmp/identical-expected"
run
if [ "$status" -eq 0 ] && linked && [ "$(ls -A .claude)" = skills ] &&
  diff -r "$tmp/identical-expected" .agents/skills >/dev/null; then
  result pass "identical overlap: links .claude/skills and keeps the skill"
else
  result fail "identical overlap: links .claude/skills and keeps the skill"
fi

# Disjoint: a different skill in each folder.
repo disjoint
skill .claude/skills deploy "Run make deploy-staging first."
skill .agents/skills review "Review the diff."
mkdir "$tmp/disjoint-expected"
cp -R .claude/skills/deploy .agents/skills/review "$tmp/disjoint-expected/"
run
if [ "$status" -eq 0 ] && linked && [ "$(ls -A .claude)" = skills ] &&
  diff -r "$tmp/disjoint-expected" .agents/skills >/dev/null &&
  git ls-files --error-unmatch .agents/skills/deploy/SKILL.md .agents/skills/review/SKILL.md >/dev/null 2>&1; then
  result pass "disjoint: moves deploy into .agents/skills and stages both skills"
else
  result fail "disjoint: moves deploy into .agents/skills and stages both skills"
fi

# Running it twice: a second run in the same repo changes nothing.
before=$(snapshot)
run
if [ "$status" -eq 0 ] && [ "$(snapshot)" = "$before" ]; then
  result pass "second run: exits 0 and changes nothing"
else
  result fail "second run: exits 0 and changes nothing"
fi

# A skill in .agents/skills that links back into .claude/skills would break
# once .claude/skills is gone, so the original has to stay.
repo linked-back
skill .claude/skills deploy "Run make deploy-staging first."
mkdir -p .agents/skills
ln -s ../../.claude/skills/deploy .agents/skills/deploy
before=$(snapshot)
run
if [ "$status" -eq 1 ] && [ "$(snapshot)" = "$before" ] && [ -f .claude/skills/deploy/SKILL.md ]; then
  result pass "linked back: puts .claude/skills back and exits 1"
else
  result fail "linked back: puts .claude/skills back and exits 1"
fi

# .agents/skills as a link to .claude/skills: deleting .claude/skills would
# delete the only copy, so the script stops first.
repo agents-is-link
skill .claude/skills deploy "Run make deploy-staging first."
mkdir -p .agents
ln -s ../.claude/skills .agents/skills
before=$(snapshot)
run
if [ "$status" -eq 1 ] && [ "$(snapshot)" = "$before" ]; then
  result pass ".agents/skills is a link: exits 1 and changes nothing"
else
  result fail ".agents/skills is a link: exits 1 and changes nothing"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All link-skills checks passed"
