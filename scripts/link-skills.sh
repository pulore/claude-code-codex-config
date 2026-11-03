#!/usr/bin/env bash
# Keeps skills in .agents/skills, where Codex loads them, and points
# .claude/skills, where Claude Code loads them, at the same directory.
# If .claude/skills is a real directory, its skills move to .agents/skills
# first. Safe to run more than once.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

mkdir -p .agents/skills .claude
if [ -d .claude/skills ] && [ ! -L .claude/skills ]; then
  cp -R .claude/skills/. .agents/skills/ && rm -r .claude/skills
fi
ln -sfn ../.agents/skills .claude/skills
git add .agents/skills .claude/skills
