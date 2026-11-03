#!/usr/bin/env bash
# .agents/hooks/guard-bash.sh
# Shared PreToolUse guard for Claude Code and Codex. Needs jq.
# Only "deny" is used, because Codex does not support "ask" from a hook yet.
set -euo pipefail
cmd="$(jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

if grep -Eq '(^|[^[:alnum:]_])\.env($|[^[:alnum:]_r])' <<<"$cmd"; then
  deny "This repo keeps secrets in .env files. Ask the user for the value you need."
fi
if grep -Eq -- '--dangerously-bypass-approvals-and-sandbox|--dangerously-bypass-hook-trust|--yolo|--dangerously-skip-permissions' <<<"$cmd"; then
  deny "Starting an agent with its sandbox, approvals or hook checks turned off is blocked here."
fi
if grep -Eq 'ANTHROPIC_BASE_URL|chatgpt_base_url|openai_base_url' <<<"$cmd"; then
  deny "Changing the model API endpoint is blocked here."
fi
exit 0
