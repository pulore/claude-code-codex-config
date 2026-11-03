---
name: pr-description
description: Drafts a pull request title and description from the current branch's commits and diff. Use when the user asks for a PR description or a summary of their branch.
---

# Draft a pull request description

1. Find where the branch starts: `git merge-base HEAD origin/main`. If there's no `origin/main`, use `main`.
2. Read the commits with `git log --oneline <base>..HEAD` and the size of the change with `git diff --stat <base>...HEAD`. Open the full diff only for the files you need to understand.
3. Write a title of 72 characters or fewer in the imperative, such as "Add retries to the webhook sender".
4. Write the description in three short parts:
   - **What changed:** two to four sentences in plain language.
   - **Why:** the problem it solves. Link the issue if a commit mentions one.
   - **Testing:** the commands from AGENTS.md that you ran and what they showed. If you ran none, say so.
5. Show the draft to the user. Don't push, open the pull request or post it anywhere.
