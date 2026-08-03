# Releasing the Mac companion

The companion ships outside the App Store — it spawns the OpenCode CLI and
reads the user's real repos, so it can't be sandboxed. Distribution is a
Homebrew cask for discovery plus Sparkle for updates, the same pipeline
Tomte runs.

## One-time setup

1. **Notary credentials** (interactive; never scripted):
   ```sh
   xcrun notarytool store-credentials opencodego-notary \
     --apple-id <your Apple ID> --team-id 7NHJT99NX8
   ```
   using an app-specific password from appleid.apple.com.

2. **Update-signing keypair**:
   ```sh
   scripts/setup-signing-key.sh
   ```
   Paste the printed public key into `app/project.yml` as `SUPublicEDKey`
   (replacing `REPLACE_WITH_SPARKLE_PUBLIC_KEY`). The private half lives in
   the login keychain — **back it up**. Losing it means no shipped app can
   ever install another update; the only remedy is making every user
   reinstall by hand. `scripts/release.sh` refuses to run while the
   placeholder is in place.

3. **Tap repo**: create `tjameswilliams/homebrew-tap` with a `Casks/`
   directory. `packaging/opencodego.rb` is copied there on each release,
   which is what `brew install --cask tjameswilliams/tap/opencodego` reads.

## Each release

```sh
scripts/release.sh 0.2.0      # archive, sign, notarize, dmg, appcast
scripts/publish.sh 0.2.0      # GitHub release + cask stamp + appcast commit
cp packaging/opencodego.rb ../homebrew-tap/Casks/opencodego.rb   # then commit there
```

`release.sh` alone (with `--skip-notarize`) is fine for a local smoke test;
never publish an un-notarized dmg — Gatekeeper will refuse it on any Mac
but this one.

## How the two update paths coexist

- **Homebrew** installs the app and, because the cask declares
  `auto_updates true`, then stays out of the way — `brew upgrade` won't
  fight the in-app updater.
- **Sparkle** does the actual updating, checking
  `dist/updates/appcast.xml` (served raw from this repo) and verifying each
  dmg's EdDSA signature before installing.

Version numbers: `MARKETING_VERSION` is the human version (`0.2.0`);
`CURRENT_PROJECT_VERSION` is a UTC datestamp, so it's monotonic without
bookkeeping — Sparkle compares that to decide what's newer.

## The phone

App Store, via Xcode's organizer or fastlane later. The iOS app has no
Sparkle equivalent and needs none.
