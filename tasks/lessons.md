# Lessons Learned

## 2026-02-25

- When asked to "fix `tasks/audit.md`", confirm whether the user wants document edits or implementation of the findings; default to remediating the audited issues in code and tests when intent is ambiguous.

## 2026-03-05

- For file edits, always use the `apply_patch` tool directly instead of invoking patch flows through shell commands.
- Keep `README.md` beginner-first and elegant; move advanced API seams/injection patterns to detailed docs instead of front-loading them in README.
