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

2. **Update-signing keypair** — ✅ done.

   `scripts/setup-signing-key.sh` found the existing key in the login
   keychain and reused it, so **Go for OpenCode signs updates with the same
   key as Tomte**. That is Sparkle's intended design, not an accident: its
   own tooling states *"You only need one signing key, no matter how many
   apps you embed Sparkle in,"* and there is no per-app account option.

   The consequence worth knowing: one key, one blast radius. Losing or
   leaking it affects **both** products, and no shipped copy of either can
   ever install another update — the only remedy is making every user
   reinstall by hand. Back up the keychain item ("Private key for signing
   Sparkle updates"); `generate_keys -x <file>` exports it if you want an
   offline copy.

3. **Tap repo**: create `tjameswilliams/homebrew-tap` with a `Casks/`
   directory. `packaging/opencodego.rb` is copied there on each release,
   which is what `brew install --cask tjameswilliams/tap/opencodego` reads.
   The cask downloads the same artefact Sparkle updates from, so a brew
   install and an in-app update can never disagree.

## Each release

```sh
scripts/release.sh 1.0                 # archive, sign, notarize, dmg, appcast
website/scripts/deploy.sh              # site + dmg + appcast → S3/CloudFront
# then stamp packaging/opencodego.rb with the printed sha256 and copy it to
# the tap repo: tjameswilliams/homebrew-tap → Casks/opencodego.rb
```

`release.sh` alone (with `--skip-notarize`) is fine for a local smoke test;
never publish an un-notarized dmg — Gatekeeper will refuse it on any Mac
but this one.

## How the two update paths coexist

- **Homebrew** installs the app and, because the cask declares
  `auto_updates true`, then stays out of the way — `brew upgrade` won't
  fight the in-app updater.
- **Sparkle** does the actual updating, polling
  `https://goforopencode.com/downloads/appcast.xml` and verifying each dmg's
  EdDSA signature before installing. That URL is compiled into every shipped
  build and installed copies poll it forever, so it must not move.

Version numbers: `MARKETING_VERSION` is the human version (`0.2.0`);
`CURRENT_PROJECT_VERSION` is a UTC datestamp, so it's monotonic without
bookkeeping — Sparkle compares that to decide what's newer.

## The phone

App Store, via Xcode's organizer or fastlane later. The iOS app has no
Sparkle equivalent and needs none.
