# Signing and notarization

The repository contains no signing keys or passwords. Use an Apple Developer ID Application certificate from your own keychain.

```sh
./scripts/build.sh
export SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
./scripts/sign.sh
./scripts/package.sh
export NOTARY_PROFILE='your-saved-profile'
./scripts/notarize.sh
```

Create a keychain profile interactively using `xcrun notarytool store-credentials` if you do not already have one. Do not paste credentials into source or a public issue. Apple notarization uploads the release artifact to Apple. Signing alone is not notarization; public releases should be accepted, stapled, and Gatekeeper-verified.

Inspect signatures with `codesign --verify --deep --strict --verbose=2 build/IOGuard.app` and `codesign -dv --verbose=4 build/IOGuard.app`. Validate the DMG ticket with `xcrun stapler validate dist/IOGuard-1.1.0-universal.dmg`.

Official Apple references: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution and https://developer.apple.com/documentation/security/customizing-the-notarization-workflow

## First-time setup on this Mac
Run `./scripts/Setup-Notarization.command` in Terminal. Apple’s tool asks for your Apple Account email, app-specific password, and Developer Team ID and stores them in the local keychain under `IOGuard`. Generate an app-specific password at https://account.apple.com/ (Sign-In and Security → App-Specific Passwords). Never paste it into chat. Your Apple Developer membership and Developer ID certificate are separate from this saved command-line login. Once saved, set `NOTARY_PROFILE=IOGuard` when running notarize.sh.
