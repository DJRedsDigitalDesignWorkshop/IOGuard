# IOGuard project instructions

- Author: djred. Canonical project: `~/Documents/IOGuard`.
- Use subagents when useful; prefer gpt-6-luna at max reasoning.
- Preserve the working Universal Audio Guard CLI and its Git history.
- Version all software changes using VERSION, the app metadata, and CHANGELOG.md.
- Commit verified project changes by default and push the matching GitHub remote.
- Build a universal Apple Silicon/Intel app and DMG. Never claim notarization without an accepted submission and validated staple.
- Use the lock-over-speakers artwork for app, menu bar, DMG file, and mounted installer volume icons.
- Do not commit credentials, signing keys, local preferences, build caches, or notarization credentials.
- Do not replace or stop the user's installed legacy guard until the app has been validated and migration is explicit. Never run two guards concurrently during audio tests.
- Preserve one-second delayed restoration after audio device changes. A selected Sound setting alone is insufficient proof of audible routing.
- Keep PLAN.md, ENGINEERING.md, MEMORY.md, and CHANGELOG.md consistent with verified results. Clearly label untested behavior.
