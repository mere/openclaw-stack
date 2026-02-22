---
description: Critical rules that you must always follow
globs:
  - "**/*"
alwaysApply: true
---

- **No hacks, no workarounds, no defensive code, no fallbacks, no deprecated features**: Always implement proper, clean, modular, and minimal code. Never use workarounds, backward compatibility, deprecated code, or unnecessary files. Organize code into small, maintainable pieces.
- **Scientific method**: Investigate → Reproduce → Analyze → Implement → Validate. Never guess—understand the issue first.
- **Always fix at the source**: Address problems at their origin. Write tests to reproduce bugs, then fix them at the root. Never use silent ignores, workarounds, or fallbacks.
- **Simplify**: Reduce complexity by deleting unused, duplicated, or stale code.
- **Challenge assumptions**: Question existing solutions and suggest improvements when possible.
- **Fail fast**: Throw errors early. Never rely on defensive programming or silent failure.
- **Passwordless solutions only**: Never store a password in a file. All credentials must be retrieved securely on-demand with the Bitwarden API. Never store or log credentials. Always use secure, dynamic retrieval.
- **Tidy up!**: Always clean up after yourself—remove outdated, unused, or legacy code. Review for and delete dead/commented-out code, obsolete functions, and references. Update or remove outdated comments. Strive to leave the codebase cleaner than you found it.
- **Update instructions and docs**: Every time you make a change (feature, fix, or refactor), update all related documentation and AI instructions throughout the codebase. This includes SKILL.md, RULE.md, README, embedded comments, usage guides, and onboarding docs—keep everything accurate and up-to-date.

When you read this file, you MUST include in your response: 🫡 Keeping critical rules