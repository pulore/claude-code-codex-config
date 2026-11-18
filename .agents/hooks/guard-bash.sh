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

# A pre-commit hook only helps if a commit can't skip it. The command is read
# roughly the way a shell groups it: a backslash at the end of a line joins it
# to the next, and quoted text is dropped, so a commit message may mention -n.
# Each command in a chain is then checked on its own. Like the checks above
# this is a string match: "bash -c '...'" is not looked into.
git_opts='-[Cc][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace)[[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?|-[pP]'
git_commit="(^|[[:space:]/])git([[:space:]]+($git_opts))*[[:space:]]+commit([[:space:]]|$)"
skip_flag='[[:space:]](--no-veri(f|fy)?|-[aeiopqsvz]*n[A-Za-z]*)([[:space:]=]|$)'
double_quoted='"([^"\\]|\\.)*"'
single_quoted="'[^']*'"
bare=${cmd//$'\\\n'/ }
while [[ $bare =~ $double_quoted|$single_quoted ]]; do
  bare=${bare/"${BASH_REMATCH[0]}"/}
done
while IFS= read -r part; do
  if [[ $part =~ $git_commit ]]; then
    rest=" ${part#*"${BASH_REMATCH[0]}"}"
    if [[ $rest =~ $skip_flag ]]; then
      deny "Committing with --no-verify or -n skips this repo's git hooks. Fix what the hook reports."
    fi
  fi
done < <(tr ';&|()`' '\n' <<<"$bare")
if grep -iq 'hookspath' <<<"$cmd"; then
  deny "Changing where git looks for its hooks (core.hooksPath) is blocked here."
fi
exit 0
