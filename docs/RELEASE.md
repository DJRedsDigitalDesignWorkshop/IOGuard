# Release checklist

- Update VERSION, CHANGELOG.md, and app-visible version.
- Build with scripts/build.sh; verify `lipo -archs build/IOGuard.app/Contents/MacOS/IOGuard` lists arm64 and x86_64.
- Inspect the preferences window, menu-bar template artwork, About icon, and missing-device handling.
- Test preference persistence, pause/resume, and selected device restoration while the legacy guard is stopped.
- Verify actual sound after screen sharing; do not rely only on the default name.
- Sign app with Developer ID and verify its signature.
- Package DMG, verify its app payload and Applications link, custom DMG icon, and custom mounted-volume icon.
- Notarize, staple, validate, and recalculate SHA-256 checksums before public release.
- Commit source and push matching GitHub repository; tag the exact tested commit.
- Upload DMG and SHA-256 to GitHub Releases. Keep a release draft until notarization succeeds.

Never upload certificates, private keys, or Apple credentials. `dist/` is ignored in Git; attach binaries to the release.
