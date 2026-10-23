# Contributing

Read AGENTS.md and ENGINEERING.md before changing routing. Keep dependencies minimal, preserve the delayed restore, and never cycle devices periodically; use only the shared, bounded recovery engine for an enabled event-triggered recovery. Include a macOS version, interface model, app, and exact reproduction steps with bug reports. Do not include private audio or credentials.

Build both architectures with scripts/build.sh. Verify device selection, pause, unplug/reconnect handling, launch-at-login status, and actual routing with a controlled sound source. Bump VERSION and CHANGELOG.md for software releases. Signed and notarized release artifacts are built by the maintainer; keys never enter Git.
