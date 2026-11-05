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

# An event with no command passes through untouched.
check "allow  (no command)" '{"tool_name":"Bash","tool_input":{}}' ""

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All hook checks passed"
