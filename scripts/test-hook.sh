#!/usr/bin/env bash
# Feeds .agents/hooks/guard-bash.sh the PreToolUse event that Claude Code and
# Codex both send for a shell command, and checks the exact output: a deny
# decision for each command it should block, and nothing at all for each
# command it lets through. The hook only reads the command's text, so a few
# of the commands it lets through read a .env file without naming one. They
# keep that limit tested. Needs jq.
set -euo pipefail
cd "$(dirname "$0")/.."

hook=.agents/hooks/guard-bash.sh
env_reason="This repo keeps secrets in .env files. Ask the user for the value you need."
agent_reason="Starting an agent with its sandbox, approvals or hook checks turned off is blocked here."
url_reason="Changing the model API endpoint is blocked here."
commit_reason="Committing with --no-verify or -n skips this repo's git hooks. Fix what the hook reports."
hooks_path_reason="Changing where git looks for its hooks (core.hooksPath) is blocked here."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

# The event both tools send: tool_name is Bash, the command is in tool_input.command.
event() {
  jq -cn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}'
}

# The exact bytes the hook prints to deny a command.
deny_json() {
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$1"
  }
}
EOF
}

# Runs the hook on an event and compares its stdout with the expected bytes.
check() {
  local label=$1 input=$2 expected=$3 status=0
  printf '%s' "$expected" >"$tmp/expected"
  printf '%s\n' "$input" | "$hook" >"$tmp/actual" || status=$?
  if [ "$status" -eq 0 ] && cmp -s "$tmp/expected" "$tmp/actual"; then
    printf 'ok    %s\n' "$label"
  else
    printf 'FAIL  %s (exit %s)\n' "$label" "$status"
    diff -u "$tmp/expected" "$tmp/actual" | sed 's/^/      /' || true
    failures=$((failures + 1))
  fi
}

expect_deny() { check "deny   $1" "$(event "$1")" "$(deny_json "$2")"$'\n'; }
expect_allow() { check "allow  $1" "$(event "$1")" ""; }

if [ ! -x "$hook" ]; then
  echo "FAIL  $hook is not executable"
  exit 1
fi

expect_deny 'cat .env' "$env_reason"
expect_deny 'source .env' "$env_reason"
expect_deny 'cat services/api/.env.local' "$env_reason"
expect_deny 'cat .env.example' "$env_reason"
expect_deny 'codex exec --dangerously-bypass-approvals-and-sandbox' "$agent_reason"
expect_deny 'claude --dangerously-skip-permissions' "$agent_reason"
expect_deny 'codex --yolo' "$agent_reason"
expect_deny 'codex --dangerously-bypass-hook-trust' "$agent_reason"
expect_deny 'export ANTHROPIC_BASE_URL=x' "$url_reason"
expect_deny 'codex -c openai_base_url=http://localhost:8080' "$url_reason"

expect_allow 'cat .envrc'
expect_allow 'npm test'
expect_allow 'git status'

# These read .env files without naming one, so the hook can't see them. Only
# the sandboxes can stop them, within the limits in the README.
expect_allow 'grep -r API_KEY .'
expect_allow 'cat .e*'

# A commit that skips git's own hooks. On git 2.56 a commit with any of these
# flags or settings got past a pre-commit hook that always fails.
expect_deny 'git commit --no-verify -m "x"' "$commit_reason"
expect_deny 'git commit -n -m "x"' "$commit_reason"
expect_deny 'git commit -an -m "x"' "$commit_reason"
expect_deny 'git commit -nm "x"' "$commit_reason"
expect_deny 'git commit -m "x" --no-verify' "$commit_reason"
expect_deny 'git commit --no-veri -m x' "$commit_reason"
expect_deny 'git commit --no-verif -m x' "$commit_reason"
expect_deny 'git add . && git commit -n -m x' "$commit_reason"
expect_deny 'git add .;git commit -n -m x' "$commit_reason"
expect_deny 'git -C app commit --no-verify -m x' "$commit_reason"
expect_deny 'git --git-dir .git commit -n -m x' "$commit_reason"
expect_deny '/usr/bin/git commit -n -m x' "$commit_reason"
# The single quotes are meant: the hook has to see the literal $( ).
# shellcheck disable=SC2016
expect_deny 'echo $(git commit -n -m x)' "$commit_reason"
expect_deny $'git add .\ngit commit -n -m x' "$commit_reason"
expect_deny $'git commit\t-n -m x' "$commit_reason"

# The flag after a message that runs over several lines, which is how agents
# usually write a commit, and on a line joined with a backslash.
expect_deny $'git commit -m "subject\n\nbody" --no-verify' "$commit_reason"
expect_deny $'git commit -m "$(cat <<\'EOF\'\nsubject\n\nit\'s the body\nEOF\n)" --no-verify' "$commit_reason"
expect_deny $'git commit \\\n  --no-verify \\\n  -m x' "$commit_reason"
expect_deny 'git commit -m "fix; done" -n' "$commit_reason"
expect_deny 'git commit -m "say \"hi\"" -n' "$commit_reason"

# Anything that names hooksPath, the setting that says where git's hooks are.
expect_deny 'git -c core.hooksPath=/dev/null commit -m x' "$hooks_path_reason"
expect_deny 'git -c "core.hooksPath=/dev/null" commit -m x' "$hooks_path_reason"
expect_deny 'git config core.hooksPath /dev/null' "$hooks_path_reason"
expect_deny 'git config --unset core.hooksPath' "$hooks_path_reason"
expect_deny 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hookspath GIT_CONFIG_VALUE_0=/dev/null git commit -m x' "$hooks_path_reason"
expect_deny 'printf "[core]\n\thooksPath = /dev/null\n" >>.git/config' "$hooks_path_reason"

# Ordinary commits, and -n where it means something else.
expect_allow 'git commit -m "fix -n flag handling"'
expect_allow 'git commit -m "docs: explain --no-verify"'
expect_allow $'git commit -m "subject\n\nuse -n and --no-verify here"'
expect_allow $'git commit -m "$(cat <<\'EOF\'\nBlock --no-verify and -n\n\nIt\'s in the hook now.\nEOF\n)"'
expect_allow 'git commit --amend --no-edit'
expect_allow 'git commit -am "wip"'
expect_allow 'git commit -uno -m x'
expect_allow 'git --git-dir .git commit -m x'
expect_allow 'git log -n 5 --grep commit'
expect_allow 'git log --grep commit -n 5'
expect_allow 'git --no-pager log --grep commit -n 5'
expect_allow 'git add -n . && git commit -m x'
expect_allow 'git commit -m x && git log -n 5'
expect_allow 'git commit -m x 2>&1 | tail -n 5'
expect_allow $'git commit -m x\ngit log -n 3'
expect_allow 'npm run lint -- -n'
# git itself refuses this one as ambiguous, so the hook leaves it alone.
expect_allow 'git commit --no-ver -m x'

# The flag is inside a quoted string, which the hook drops before it looks for
# flags. Only a pre-commit hook the agent can't edit, or the sandbox, stops it.
expect_allow 'bash -c "git commit --no-verify -m x"'

# An event with no command passes through untouched.
check "allow  (no command)" '{"tool_name":"Bash","tool_input":{}}' ""

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All hook checks passed"
