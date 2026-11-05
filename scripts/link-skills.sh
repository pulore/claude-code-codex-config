#!/usr/bin/env bash
# Keeps skills in .agents/skills, where Codex loads them, and points
# .claude/skills, where Claude Code loads them, at the same directory.
#
# If .claude/skills is a real directory, its skills move to .agents/skills
# first. A skill that's in only one of the two directories, or identical in
# both, moves across. If any skill is in both with different contents, the
# script lists those skills and stops before changing anything. It deletes
# the old directory only after every skill in it reads the same through the
# new link. Safe to run more than once.
set -euo pipefail
shopt -s dotglob nullglob
cd "$(git rev-parse --show-toplevel)"

old=.claude/skills
new=.agents/skills

# True if both paths are directories with the same files, or both are files
# with the same bytes.
same() {
  if [ -d "$1" ] && [ -d "$2" ]; then
    diff -r "$1" "$2" >/dev/null 2>&1
  else
    [ ! -d "$1" ] && [ ! -d "$2" ] && cmp -s "$1" "$2"
  fi
}

# True if the path exists or is a symlink, even a broken one.
present() { [ -e "$1" ] || [ -L "$1" ]; }

if [ -L "$new" ]; then
  echo "$new is a symlink. Keep the real skills there, then run this again." >&2
  exit 1
fi

if [ -d "$old" ] && [ ! -L "$old" ]; then
  conflicts=""
  for path in "$old"/*; do
    name=${path##*/}
    if present "$new/$name" && ! same "$path" "$new/$name"; then
      conflicts+="  $name"$'\n'
    fi
  done
  if [ -n "$conflicts" ]; then
    {
      echo "These skills are in both $old and $new, with different contents:"
      printf '%s' "$conflicts"
      echo "Nothing was changed. Compare each pair with diff -r, keep the version"
      echo "you want in $new, delete it from $old, then run this again."
    } >&2
    exit 1
  fi

  mkdir -p "$new"
  for path in "$old"/*; do
    present "$new/${path##*/}" || cp -R "$path" "$new/"
  done

  # Move the old directory aside, at the same depth so relative links still
  # resolve, and check every skill through the new link. If anything fails
  # from here, the trap puts the old directory back.
  backup=$(mktemp -d "$old.XXXXXX")
  rmdir "$backup"
  mv "$old" "$backup"
  trap 'rm -f "$old"; mv "$backup" "$old"' EXIT
  ln -s ../.agents/skills "$old"
  for path in "$backup"/*; do
    name=${path##*/}
    if ! same "$path" "$old/$name"; then
      echo "$name doesn't read the same through the new link, so $old was put back." >&2
      echo "Check whether $new/$name links into $old. Skills already copied to $new are still there." >&2
      exit 1
    fi
  done
  trap - EXIT
  rm -r "$backup"
fi

mkdir -p "$new" .claude
ln -sfn ../.agents/skills "$old"
git add "$new" "$old"
