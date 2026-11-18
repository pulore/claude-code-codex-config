# Claude Code and Codex in one repo

Config for a repository where people use both Claude Code and Codex. Both agents follow one AGENTS.md, share one skills directory and run the same shell-command hook. Each also treats the other's config as read-only, because by default neither one does.

The files come from the post [Claude Code and Codex in One Repo: The Config That Keeps Both Agents on the Same Rules](https://pulore.com/blog/claude-code-and-codex-in-one-repo), which explains each choice in full. The post checked them on **Claude Code 2.1.314** and **Codex CLI 0.166.0** on 30 October 2026.

## What's in it

```
AGENTS.md                       shared rules for both agents
CLAUDE.md                       imports AGENTS.md, plus notes for Claude Code only
.agents/skills/                 skills for both tools
.claude/skills                  symlink to ../.agents/skills
.claude/settings.json           Claude Code permissions, sandbox and hook
.codex/config.toml              Codex permissions profile
.codex/hooks.json               runs the shared hook in Codex
.codex/rules/default.rules      Codex rules for commands that leave the sandbox
.agents/hooks/guard-bash.sh     the shared PreToolUse hook
scripts/link-skills.sh          creates the .claude/skills symlink
scripts/test-hook.sh            tests the hook
scripts/test-link-skills.sh     tests link-skills.sh
scripts/check-codex-profile.sh  checks the Codex profile on your machine
.github/workflows/ci.yml        runs the checks on every push and pull request
```

### AGENTS.md, plus a CLAUDE.md that imports it

AGENTS.md is the one file both tools read, so the build commands and conventions go there. The one here is an example for an npm and TypeScript project. Replace it with your own.

- **AGENTS.md has to stand on its own.** Codex reads one AGENTS.md per directory from the project root down to where you started it, and cuts them off at a combined 32 KiB: silently before Codex 0.168.0, with a warning since that release (13 Nov 2026). It doesn't expand imports: an `@` line reaches the model as plain text. So every rule is written out in full.
- **CLAUDE.md is a shim:** `@AGENTS.md`, then a "Claude Code only" section. Since 2.1.277, Claude Code reads AGENTS.md by itself, but under the default setting only when there's no CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md on the path. A teammate's personal CLAUDE.local.md would switch AGENTS.md off for them, and nothing on screen would say so. The docs also say some sessions can't read AGENTS.md directly. The import covers all of these cases and never causes a double read.

### Skills: one directory and a symlink

Codex loads skills from .agents/skills, and Claude Code loads them from .claude/skills. The real files live in .agents/skills, and .claude/skills is a symlink to it, so both tools list the same skills. `scripts/link-skills.sh` creates the link. If .claude/skills is already a real directory, the script moves its skills into .agents/skills first:

- A skill that's in only one of the two directories, or identical in both, moves across.
- If a skill is in both with different contents, the script lists every such skill and stops before changing anything. Keep the version you want in .agents/skills, delete the other, and run it again.
- It deletes the old .claude/skills only after every skill in it reads the same through the new link. If one doesn't, for example because a skill in .agents/skills links back into .claude/skills, it puts .claude/skills back and stops.

It's safe to run twice. `scripts/test-link-skills.sh` tests each of these cases, and CI runs it.

Keep skill frontmatter to `name` and `description`, so a skill behaves the same in both tools. Fields like `disable-model-invocation` are documented only for Claude Code. Keep descriptions short too, because Codex caps the initial skill list at about 2% of the context window. The example skill, `pr-description`, drafts a pull request description from the current branch.

### Permissions: each tool guards the other's files

Each tool protects its own config, and neither protects the other's. In Codex's workspace-write sandbox an agent can rewrite .claude/settings.json and .mcp.json without asking. In accept-edits mode, Claude Code changes .codex/ and AGENTS.md without a prompt. So a prompt injection that reaches either agent can rewrite the other's config.

- **`.codex/config.toml`** defines a permissions profile called `repo` and makes it the default. It extends the built-in `:workspace` profile and denies reads of `.env` and `.env.*` files. How deep that reaches depends on the platform: on Linux, WSL and native Windows it stops at `glob_scan_max_depth`, as described under [Scope and security notes](#scope-and-security-notes). It also makes `.claude`, `.mcp.json`, `CLAUDE.md` and `AGENTS.md` read-only. Codex already keeps `.codex`, `.agents` and `.git` read-only, and network access stays off.
- **`.claude/settings.json`** has three parts:
  - **Deny rules:** reading .env files, and editing Codex's config, the hook, `.mcp.json` and the settings file itself.
  - **Ask rules:** edits to AGENTS.md, CLAUDE.md and skills, and `git push`. Bypass-permissions mode is disabled.
  - **The sandbox:** it blocks writes to `.codex`, `.agents`, `.claude` and `.mcp.json`, and allows network access only to registry.npmjs.org. Deny rules only cover Claude's own file tools and simple commands like `cat .env`. A `grep -r` that never names the file gets past them, so the sandbox has to stop it. The sandbox's own `denyRead` list names only the root `.env`. Claude also adds the `Read` deny rules to it, but the sandbox ignores their glob patterns on Linux, as the scope notes describe. `failIfUnavailable` makes Claude refuse to start without the sandbox, rather than run without it after a warning. `allowUnsandboxedCommands: false` stops a failed command from being retried outside it.
- **`.codex/rules/default.rules`** decides which commands may run outside Codex's sandbox. `git push` asks first, and starting another `codex` or `claude` session is forbidden. The `match` and `not_match` lists are tests that Codex runs when it loads the file.

### One hook for both tools

Both tools send a PreToolUse event before a shell command, with the command in `tool_input.command`. Both accept the same deny response, so one script, `.agents/hooks/guard-bash.sh`, guards both. Claude Code runs it from `.claude/settings.json`, and Codex runs it from `.codex/hooks.json`. It denies commands that:

- name a .env file, such as `cat .env` or `source .env`, while letting `.envrc` through
- start an agent with its sandbox, approvals or hook checks turned off (`--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust`, `--yolo`, `--dangerously-skip-permissions`)
- change the model API endpoint (`ANTHROPIC_BASE_URL`, `chatgpt_base_url`, `openai_base_url`)
- commit with git's own hooks skipped: `git commit --no-verify`, the shortened `--no-veri` and `--no-verif` that git also accepts, and `-n` alone or in a cluster such as `-an`
- name `hooksPath`, the git setting that says where its hooks are, in any form: `git -c core.hooksPath=...`, `git config`, a `GIT_CONFIG_KEY_*` variable, or a line written into a config file

The second and third checks come from a real prompt-injection payload, which told Codex to start a child `codex exec --dangerously-bypass-approvals-and-sandbox` and told Claude to change its API base URL. The last two are there because a pre-commit hook only helps if a commit can't skip it. On git 2.56, each of those forms committed past a pre-commit hook that always fails. The hook only ever denies. Codex parses "ask" from a hook but doesn't support it yet: it marks the hook as failed and runs the command anyway. The hook needs jq.

It only reads the command's text. A command that reads a .env file without naming one, such as `grep -r API_KEY .` or `cat .e*`, gets past it. Only the sandboxes can stop those, within the limits under [Scope and security notes](#scope-and-security-notes). The commit checks drop quoted text before they look for flags, and join lines that end in a backslash. So a commit message can mention `-n`, and a flag that comes after a message of several lines is still seen. It also means a flag inside a quoted string, as in `bash -c "git commit --no-verify"`, gets past them. The `hooksPath` check denies any command that contains the word, including one that only reads the setting.

`scripts/test-hook.sh` feeds the hook fake events and checks the exact JSON it prints, including for the commands that it lets through. CI runs it on every push and pull request. CI also runs shellcheck, validates the JSON and TOML files, checks the skills symlink and the size of AGENTS.md, and runs `scripts/test-link-skills.sh`.

## Setup

1. Copy the files into the root of your repo, keeping the paths. If you already have a CLAUDE.md, move its shared rules into AGENTS.md, and keep only Claude-only notes below the import.
2. Replace the example AGENTS.md with your own commands and conventions. Keep it under 32 KiB (`wc -c AGENTS.md`), and don't put imports in it.
3. Change the npm-specific parts of `.claude/settings.json` to fit your stack: the allow list and `sandbox.network.allowedDomains`.
4. Add the lines from `.gitignore` to yours. Some global gitignores exclude `.agents`, and then `git add` refuses it. The `!.agents/` line keeps it in the repo.
5. Run `scripts/link-skills.sh`, then commit. If it lists skills that differ between .claude/skills and .agents/skills, merge each one into .agents/skills and run it again.
6. Install jq. On Linux, Claude Code's sandbox also needs bubblewrap and socat. With `failIfUnavailable` set, Claude won't start without them.
7. In Codex, trust the project. `.codex/config.toml` and `.codex/rules` load only in a trusted project. Then open `/hooks` and trust the hook. The trust is tied to the hook definition's hash, so after any change Codex skips the hook until you trust it again. Check what changed before you do.
8. Start Claude Code from the repo root, and accept the workspace trust dialog. Claude reads `.claude/settings.json` only from the directory you start it in. It applies the allow rules only after you trust the workspace, while the deny and ask rules apply right away.
9. In your personal files, `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`, add the sentence below. In the study the post cites, it raised the share of choices that followed the code over a stale instruction file from 4.2% to 91.4%.

   ```plaintext
   When a repository's documentation and its existing code
   disagree, follow the conventions used in the existing code,
   and in your final reply point out each inconsistency you
   found between the documentation and the code.
   ```

On Windows, the symlink needs Developer Mode and `git config core.symlinks true`.

## Check what each tool loaded

None of these needs a login. Run them in your own terminal, not through an agent. On macOS, Codex's sandbox can't start inside another sandbox, so from a sandboxed agent shell `codex sandbox` fails with "sandbox_apply: Operation not permitted" whatever the profile says.

```bash
# The exact prompt Codex would send (as JSON), including every AGENTS.md it loaded.
# Search it for the last line of your AGENTS.md to catch the 32 KiB cut.
codex debug prompt-input "hi" > /tmp/codex-prompt.json

# The profile in action. Both should fail.
codex sandbox -P repo -- cat .env
codex sandbox -P repo -- touch .claude/probe

# Which rule a command hits
codex execpolicy check --pretty --rules .codex/rules/default.rules -- git push origin main

# Effective sandbox settings and MCP servers
codex doctor
codex mcp list

# Ignored allow rules and sandbox glob warnings
claude doctor
claude mcp list
```

The `cat .env` check only means something when a .env file exists. With one, both commands fail with a permission error: "Operation not permitted" on macOS, and "Permission denied" for the read and "Read-only file system" for the write on Linux.

`scripts/check-codex-profile.sh` runs these profile checks for you in a throwaway repo, with sentinel files that hold no real values, so you don't need a .env of your own. It fails if a `.env` or `.env.*` file up to three directories below the root is readable, if `.envrc` isn't, or if `.claude/settings.json` or AGENTS.md is writable. Then it reports how much deeper the deny reaches on your machine. It uses its own `CODEX_HOME`, so it doesn't read or change your Codex config. Run it in your own terminal after each Codex upgrade.

Feed the hook a fake event to see it deny, or run all the hook tests:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' | .agents/hooks/guard-bash.sh
scripts/test-hook.sh
```

Inside a Claude Code session, run `/context` and look under Memory files to see which instruction files loaded.

Older docs and releases use `codex sandbox linux --permissions-profile`. Use `codex sandbox -P <profile> -- <command>` instead. Both tools change their config surface every few weeks, so rerun these checks after each upgrade. They take about a minute.

## Scope and security notes

- **The hook is a second layer.** It's a string match, behind the sandboxes. A command that reads a .env file without naming it, such as `grep -r API_KEY .`, gets past the hook, so only the sandboxes can stop it, with the limits below.
- **The commit checks cover `git commit` only.** They stop the flags that skip a pre-commit or commit-msg hook when the agent types them in a command. They don't look inside a quoted string, a git alias or a script the agent writes and runs, and they don't cover `git push --no-verify`. Keep the checks that matter in CI as well.
- **The `.env.*` patterns cover `.env.example` too**, in the deny rules, the hook and `.gitignore`. If agents should read an example file, give it a name like `env.example`.
- **The .env deny covers every process in the sandbox.** A dev server that loads .env fails there too, so start those yourself.
- **Command rules are prefix matches in both tools.** `git -C . push` matches neither `Bash(git push *)` nor the Codex push rule. Use these rules to cut down on prompts, and rely on the sandbox for anything you need blocked.
- **Codex's .env deny has a depth limit on Linux, WSL and native Windows.** There, Codex finds the files that match a deny glob by scanning the repo when each sandboxed command starts, and `glob_scan_max_depth` bounds that scan. With `glob_scan_max_depth = 4`, as set here, our Linux test with Codex CLI 0.166.0 denied `.env` and `.env.*` files up to three directories below the root, such as `a/b/c/.env`, while `cat` and `grep -r` could both read `a/b/c/d/.env`. With 8, Codex denied every depth we tried, down to six directories below the root. Raise it to cover your deepest .env file. OpenAI's docs say a deeper scan adds work before each command starts. On macOS the same profile denied every depth we tried, and OpenAI describes the scan limit only for Linux, WSL and native Windows. We haven't tested WSL or Windows.
- **On those platforms the scan also misses new files.** A file created after a sandboxed command starts isn't in that command's scan, so a process that's already running, such as a dev server or a watcher, can read a .env created after it started.
- **Claude Code's sandbox ignores globs on Linux.** It drops the glob patterns in Read and Edit rules there, and `claude doctor` warns about `Read(.env.*)`. So on Linux a command such as `grep -r` that never names a `.env.*` file can read it, and the hook doesn't stop that either.
- **Path syntax:**
  - In the Codex profile, read entries must be exact paths or a directory ending in `/**`. Other globs fail with "only supports deny access".
  - In Claude Code, path rules must use `Read(...)` or `Edit(...)`. Claude accepts `Write(...)` path rules but never matches them.
- **Nested AGENTS.md files:** Codex loads one such as `services/api/AGENTS.md` only when the session starts in that directory. The root CLAUDE.md also stops Claude from loading nested AGENTS.md files on demand. If a service needs its own rules, give it a CLAUDE.md with the same import line, and start Codex there.
- **Don't commit an AGENTS.override.md.** Codex prefers it over AGENTS.md in the same directory, and Claude never reads it. The `.gitignore` here excludes it.

## Who maintains this

[Pulore](https://pulore.com), a two-founder software studio in Dubai. If you'd like a second opinion on how your team runs coding agents, or on the rest of your architecture, see our [technical consulting](https://pulore.com/services/technical-consulting).

Issues and pull requests are welcome.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
