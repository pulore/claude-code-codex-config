# AGENTS.md

Instructions for every coding agent in this repo. Codex reads this file directly, and Claude Code reads it through CLAUDE.md. Codex doesn't expand imports, so every rule is written out here in full.

## Commands

- Install: `npm ci`
- Build: `npm run build`
- Test everything: `npm test`
- Test one file: `npm test -- src/orders/total.test.ts`
- Lint: `npm run lint`, or `npm run lint -- --fix` to fix what it can
- Type-check: `npm run typecheck`

Before you say a change is done, run the lint, the type-check and the tests that cover it, and say which ones you ran.

## Conventions

- npm is the package manager. Don't add a pnpm or yarn lockfile. Commit changes to package-lock.json with the change that caused them.
- TypeScript in strict mode. Don't use `any`. If you can't avoid it, add a comment that says why.
- Code lives in `src/`. Each test sits next to the file it tests, named `<name>.test.ts`.
- File names are kebab-case.
- Keep each change to one concern. Don't reformat or rename code you weren't asked to touch.
- Commit messages start with a short imperative subject, such as "Add retries to the webhook sender", followed by a body that says why.

## Secrets

- Secrets live in `.env` files, and agents can't read them in this repo. If you need a value, ask the user. Never guess one or hard-code it.
- Never print, log or commit secrets, tokens or customer data.
- The dev server reads `.env`, so it won't start inside an agent's sandbox. Ask the user to start it.

## Agent config

- AGENTS.md, CLAUDE.md, `.claude/`, `.codex/`, `.agents/` and `.mcp.json` control how agents work in this repo. Change them only when the user asks, and say what you changed.
- Rules for every agent go in this file. Notes for Claude Code alone go in CLAUDE.md, below the import.
- Don't push, publish or open pull requests unless the user asks.
