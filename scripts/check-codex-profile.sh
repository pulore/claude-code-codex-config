#!/usr/bin/env bash
# Checks the Codex profile in .codex/config.toml on this machine. It copies
# the agent config into a throwaway repo, adds sentinel files that hold no
# real values, and runs commands in Codex's sandbox against them. Needs the
# Codex CLI, and must run in your own terminal, because Codex's sandbox
# can't start inside another agent's sandbox. CI doesn't run it, since CI
# doesn't install Codex.
#
# It fails if a .env or .env.* file up to three directories below the root
# is readable, if .envrc isn't, or if Claude Code's files or AGENTS.md are
# writable. Then it reports how much deeper the deny reaches. On Linux, WSL
# and native Windows, glob_scan_max_depth in the profile bounds that.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if ! command -v codex >/dev/null; then
  echo "codex isn't on PATH. Install the Codex CLI first." >&2
  exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/.codex" "$tmp/repo/.claude" "$tmp/codex-home"
repo="$(cd "$tmp/repo" && pwd -P)"
cp .codex/config.toml "$repo/.codex/"
cp .claude/settings.json "$repo/.claude/"
cp AGENTS.md "$repo/"
git -c init.defaultBranch=main init -q "$repo"

# A separate CODEX_HOME that trusts only the throwaway repo, so your own
# Codex config is neither read nor changed.
export CODEX_HOME="$tmp/codex-home"
printf '[projects."%s"]\ntrust_level = "trusted"\n' "$repo" >"$CODEX_HOME/config.toml"

dirs="d1 d1/d2 d1/d2/d3 d1/d2/d3/d4 d1/d2/d3/d4/d5 d1/d2/d3/d4/d5/d6"
for d in . $dirs; do
  mkdir -p "$repo/$d"
  for f in .env .env.local; do
    echo "SENTINEL-NOT-A-SECRET $d/$f" >"$repo/$d/$f"
  done
done
echo "SENTINEL-NOT-A-SECRET .envrc" >"$repo/.envrc"

cd "$repo"
sandboxed() { codex sandbox -P repo -- "$@" >/dev/null 2>&1; }

if ! out=$(codex sandbox -P repo -- true 2>&1); then
  echo "Codex couldn't start its sandbox here. Run this in your own terminal." >&2
  printf '%s\n' "$out" | grep -v 'PATH aliases' | tail -3 >&2
  exit 2
fi
echo "$(codex --version 2>/dev/null | tail -1) on $(uname -sm), glob_scan_max_depth $(sed -n 's/^glob_scan_max_depth = //p' .codex/config.toml)"

failures=0
for f in .env .env.local d1/.env d1/d2/.env d1/d2/d3/.env d1/d2/d3/.env.local; do
  if sandboxed cat "$f"; then
    echo "FAIL  readable: $f"
    failures=$((failures + 1))
  else
    echo "ok    denied:   $f"
  fi
done
if sandboxed cat .envrc; then
  echo "ok    readable: .envrc"
else
  echo "FAIL  denied:   .envrc"
  failures=$((failures + 1))
fi
for f in .claude/settings.json AGENTS.md; do
  if sandboxed sh -c "echo x >> $f"; then
    echo "FAIL  writable: $f"
    failures=$((failures + 1))
  else
    echo "ok    read-only: $f"
  fi
done

echo "Deeper files (readable means the scan stopped above them):"
for d in d1/d2/d3/d4 d1/d2/d3/d4/d5 d1/d2/d3/d4/d5/d6; do
  if sandboxed cat "$d/.env"; then
    echo "      readable: $d/.env"
  else
    echo "      denied:   $d/.env"
  fi
done

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All Codex profile checks passed"
