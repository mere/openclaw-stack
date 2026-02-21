# LOGTHIS Command

## Description

When the user types `LOGTHIS` in the chat, create a changelog entry summarizing the current session's achievements. 



## What to Do

1. **Respond with**: "🫡 MiniSpec: CREATING CHANGELOG! 🫡"
2. **Summarize** session achievements
3. **Update** CHANGELOG.md with Common Changelog format

Create changelog entry summarizing completed implementation.

- **File**: `CHANGELOG.md` (project root)
- **Format**: [Common Changelog](https://common-changelog.org) format
- **Version**: Semver (determine bump based on changes)
- **Date**: YYYY-MM-DD format
- **Order**: Latest entries at top
- **Commit**: Add all changed files, commit with Conventional Commits + emoji

**Idempotency**: Append single entry per commit hash; skip if entry exists for same commit.


4. **Bump version** in relevant package.json file(s) based on change type:
   - **Patch** (x.x.X): Bug fixes, minor corrections
   - **Minor** (x.X.x): New features, enhancements (backward compatible)
   - **Major** (X.x.x): Breaking changes, major refactors
   - Determine version bump based on the nature of changes in the session
6. **Add** all changed files to git (not just changelog)
7. **Commit** all changes with Conventional Commits + emoji
8. **Push** git push the changes