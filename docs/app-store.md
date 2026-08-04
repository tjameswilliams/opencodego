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

- [x] **Rename** — "Go for OpenCode" (2026-08-03).
- [x] Subtitle: "Steer your Mac's coding agent" — the compatibility claim
      lives in the subtitle and description, where it is descriptive,
      rather than in the name.
- [ ] **Confirm export-compliance answer** (see above).
- [x] **`aps-environment` per configuration** — Debug uses
      `Phone/Phone.entitlements` (development), Release uses
      `Phone/Phone.release.entitlements` (production). Verified the build
      setting resolves correctly per config.
      **Still to verify at export:** a locally archived build signed with a
      *development* profile reports `aps-environment: development`
      regardless, because entitlements are intersected with what the
      profile grants. The production value only appears once exported with
      `method: app-store` against a distribution profile — check it there,
      not in the archive.
- [ ] Confirm the CloudKit container is deployed to the **Production**
      environment. Development-environment schema does not exist in
      production, so pairing would fail for every real user. This is the
      classic first-release CloudKit failure.
- [x] Screenshots for the 6.5" slot (4 uploaded).
- [ ] **App previews** — encoded and waiting at
      `~/Downloads/goforopencode-previews/`, but they must be dragged into
      App Store Connect by hand. ASC's uploader accepts a programmatic
      file assignment and then silently discards it, so this step cannot
      be automated from the browser.

      Source recordings are 60fps HEVC at 1206x2622, which is valid for
      none of it. Each preview is re-encoded to H.264, 30fps, 1242x2688 —
      scaled to width and cropped 12px of height, so nothing is stretched.

      Duration is the constraint worth remembering: previews must be
      **15-30s**. `diff_viewer` and `coding_session` were over and are
      trimmed; the pairing recording was *under*, at 10.9s, and shorter
      still once Control Center was cut at 9.1s. It holds its final frame
      to reach 15.2s. `01-pairing-slowed.mp4` is the same footage eased to
      0.72x with a 3s hold instead of 6.2s of freeze.
- [x] Support URL → the GitHub repo; Marketing URL →
      `https://goforopencode.com`; Privacy Policy URL →
      `https://goforopencode.com/privacy` (the App Privacy page, not the
      version page). Category is Developer Tools.
- [x] **Open source stated on the product page** — a description section
      and the promotional text. Both name the **PolyForm Noncommercial**
      licence rather than saying "open source" unqualified: PolyForm
      Noncommercial restricts commercial use, so it is source-available
      and *not* OSI-approved. Saying "open source" with the licence named
      in the same sentence is honest; saying it alone would be
      open-washing, which this audience notices.
- [ ] Review-notes text explaining that the app **requires a Mac running
      the companion** to do anything. Without a demo path, a reviewer sees
      a pairing screen and nothing else — this is the second most likely
      rejection after the name. Consider either supplying a demo video, or
      a review-mode build with a canned transcript.
- [ ] Age rating and export-compliance answers in App Store Connect.
- [x] **App Privacy questionnaire** — answered "No, we do not collect
      data from this app" and published; the product page now shows **Data
      Not Collected**. This is a separate requirement from the
      privacy-policy URL, which does not satisfy it.

      The answer is defensible and consistent with everything already
      shipped: no backend, no analytics, no third-party SDKs, and
      `PrivacyInfo.xcprivacy` already declares no collection. Apple's
      definition turns on data *we* can access — prompts and code go only
      to the user's own Mac, and pairing records live in the user's own
      CloudKit private database, which the developer cannot read. Answering
      "yes" would have contradicted the shipped manifest. Responses are
      editable and re-publishable if that ever stops being true.

## Uploading a build: error 90129

**`CFBundleName` must be set explicitly in `project.yml`.** Unset, it
falls through to `$(PRODUCT_NAME)`, which is the *target* name — `Phone`
— and App Store Connect rejects the upload:

> 90129: The bundle uses a bundle name or display name that is already
> taken.

`Phone` is one of Apple's own apps, so the name is reserved. Setting
`CFBundleDisplayName` alone is not enough; both keys are checked.

What makes this expensive is *where* it fails. The rejection happens
during processing, **after** the upload completes, so Xcode reports a
successful upload and the build simply never appears in TestFlight. The
only trace is TestFlight → Build Uploads, where it shows as **Failed** —
that list is the first place to look whenever a build goes missing, not
the Builds list, which only ever shows successes.

Two 1.0 (1) uploads were lost to this on 2026-08-03 before the cause was
found. `CURRENT_PROJECT_VERSION` was bumped to `2` afterwards, since a
failed upload can still hold its build number.

The `.app` is still named `Phone.app` — that is `PRODUCT_NAME` and Apple
does not check it, so renaming the product is optional.

## The real blocker is not paperwork

**Nothing has been verified on a device beyond LAN pairing and a typed
prompt.** Built but never run against real hardware:

- the hole-punched path — the product's entire "from anywhere" claim
- push, including approve-from-notification
- attachments, camera, dictation
- Plan mode, todos, working-tree review, slash commands

Shipping the headline feature without once confirming it works is the
kind of thing that produces one-star reviews rather than a rejection,
which is worse. **The order that makes sense: device test pass →
TestFlight → submit.** TestFlight is also the cheapest way to find out
whether the production CloudKit container is actually configured, since
that failure is invisible until a build runs outside the development
environment.

## Not blocking, worth knowing

- **Local Network permission** appears on first pairing. The purpose
  string explains it, but the pairing screen should too — a denied prompt
  looks like a broken app.
- **Background execution**: the app deliberately does not request
  background modes. Turns survive backgrounding because the *Mac* keeps
  working and the phone resumes — no background entitlement needed, which
  is also one fewer review question.
