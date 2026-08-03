# App Store readiness

Audited 2026-08-03. The iPhone app is the submission; the Mac companion
ships via Homebrew/dmg and is **not** an App Store product (it isn't
sandboxable — it spawns the OpenCode CLI — and it self-updates via
Sparkle, which App Store apps may not do).

---

## ⚠️ Blocking risk: the app's name

**"OpenCode Go" contains another project's name.** Two separate problems:

1. **App Review Guideline 5.2.1 (Intellectual Property).** Apple rejects
   apps whose name or icon uses a third party's trademark in a way that
   could suggest affiliation. A disclaimer in the README is not visible in
   App Store search results, where the name does its work.
2. **OpenCode's own request.** Their repository asks third-party products
   using "OpenCode" in their names to state clearly that they are
   unaffiliated. We do state it — but complying with their request does
   not resolve Apple's rule, which is about consumer confusion, not the
   upstream project's permission.

**Recommendation: rename before submitting.** A distinct product name with
"for OpenCode" *in the subtitle or description* rather than the name is the
pattern that passes review — the name is yours, the compatibility claim is
descriptive. The mark itself needs no change: `OC/GO` reads as an
abbreviation of whatever the product is called.

If the name stays, the realistic outcome is a 5.2.1 rejection, and the
remedy at that point is the same rename plus another review cycle.

This is the single highest-risk item in this document. Everything else is
mechanical.

---

## Encryption / export compliance

`ITSAppUsesNonExemptEncryption` is currently `false`.

**Verify this before submitting.** The app performs genuine end-to-end
encryption of user content (Curve25519 key agreement, ChaCha20-Poly1305
sealing) using CryptoKit. Apps using *only* encryption provided by the
operating system are generally exempt, and CryptoKit is Apple-provided —
but the exemption turns on what the encryption is *for*, and "protecting
arbitrary user content in transit" is a stronger claim than
"authentication only".

Options, in order of preference:
1. Confirm the exemption applies and keep `false` (most likely correct,
   but confirm rather than assume — this is a legal determination, not an
   engineering one).
2. Set `true` and file the annual self-classification report with BIS.

France also requires a separate declaration for apps distributed there.

---

## Done

- [x] **Privacy manifest** (`Phone/PrivacyInfo.xcprivacy`) — mandatory
      since 2024. Declares no collection, no tracking, and reasons for the
      two required-reason APIs touched (UserDefaults `CA92.1`, file
      timestamps `C617.1`). Verified present in the built bundle.
- [x] **Purpose strings** for every gated capability: local network,
      camera, microphone, speech recognition, Face ID. All say what the
      feature does *and* where the data goes.
- [x] **Third-party notices** (`NOTICE.md`) — Sparkle's MIT text
      reproduced as its licence requires; OpenCode's noted although not
      bundled; SF Symbols usage constrained to interface glyphs.
- [x] **No bundled fonts** — the wordmark is generated geometry, so no
      font licence applies.
- [x] **Sparkle is Mac-only.** Confirmed: the iOS target does not link it.
- [x] **No analytics, no telemetry, no third-party SDKs.** The only
      network destinations are the user's own Mac and their own iCloud.

## Before submitting

- [ ] **Rename** (see above).
- [ ] **Confirm export-compliance answer** (see above).
- [ ] Flip `aps-environment` to `production` for the release build —
      `project.yml` currently pins `development`, which is right for
      TestFlight-from-Xcode but wrong for a store build.
- [ ] Confirm the CloudKit container is deployed to the **Production**
      environment. Development-environment schema does not exist in
      production, so pairing would fail for every real user. This is the
      classic first-release CloudKit failure.
- [ ] Screenshots for every required device size.
- [ ] Support URL and privacy-policy URL (a page stating the app collects
      nothing is sufficient, and true here).
- [ ] Review-notes text explaining that the app **requires a Mac running
      the companion** to do anything. Without a demo path, a reviewer sees
      a pairing screen and nothing else — this is the second most likely
      rejection after the name. Consider either supplying a demo video, or
      a review-mode build with a canned transcript.
- [ ] Age rating, category (Developer Tools), and export-compliance
      answers in App Store Connect.

## Not blocking, worth knowing

- **Local Network permission** appears on first pairing. The purpose
  string explains it, but the pairing screen should too — a denied prompt
  looks like a broken app.
- **Background execution**: the app deliberately does not request
  background modes. Turns survive backgrounding because the *Mac* keeps
  working and the phone resumes — no background entitlement needed, which
  is also one fewer review question.
