#!/bin/zsh
set -eu
print 'IOGuard notarization setup'
print 'This saves Apple notarization credentials in your own macOS keychain.'
print 'Enter your Apple Account email, app-specific password, and Developer Team ID when Apple’s tool asks.'
print 'Use an app-specific password from account.apple.com; do not use your normal Apple Account password.'
print 'Find your Team ID in your Apple Developer account under Membership details.'
print 'Nothing is sent to GitHub or chat by this script.'
xcrun notarytool store-credentials IOGuard
print 'Profile IOGuard saved. Return to Codex to finish notarization and publish the release.'
