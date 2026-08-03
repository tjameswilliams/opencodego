# Working on this app

## Never build the Mac companion unsigned into Xcode's DerivedData

```sh
# WRONG — writes an adhoc-signed app into the folder Xcode runs from
xcodebuild -scheme MacCompanion CODE_SIGNING_ALLOWED=NO build

# RIGHT — verification builds go somewhere else entirely
xcodebuild -scheme MacCompanion -derivedDataPath /tmp/verify-dd build
```

The companion stores its pairing private key in the login keychain. Keychain
ACLs are bound to the app's code signature, so an adhoc-signed build cannot
read an item created by the Apple-Development-signed build Xcode produces.
The symptom is a **keychain error -25293** (`errSecAuthFailed`) at pairing
time, and it looks like a bug in the pairing code rather than what it is:
two differently-signed copies of the same app fighting over one keychain
item.

`PairingKeyStore` now recovers — an unreadable key is a dead pairing by
definition, so it drops it and mints a new one rather than dead-ending the
user at an error. But recovery costs a re-pair, so don't cause it.

The iOS target is unaffected (simulator builds don't share a keychain with
device builds), but use `-derivedDataPath` there too out of habit.

## Regenerating the Xcode project

`app/OpenCodeGo.xcodeproj` is generated and gitignored:

```sh
cd app && xcodegen generate
```

Run it after adding or removing any source file — a new `.swift` that
isn't in the project produces a "cannot find X in scope" error that looks
like a typo.

## Iterating on UI without a paired Mac

`tools/uiharness` compiles the real Phone views against mock state:

```sh
cd tools/uiharness && xcodegen generate
xcodebuild -project Harness.xcodeproj -scheme Harness \
  -destination 'id=<booted simulator udid>' build
xcrun simctl install booted <path to Harness.app>
xcrun simctl launch booted com.timwilliams.harness.ui
```

It builds the actual source files rather than copies, so what you see is
what ships.

## Two stale-state traps

1. **The Mac companion is a menu bar app people leave running.** Rebuilding
   in Xcode does not replace a running instance. A phone talking to a stale
   companion gets "this Mac's OpenCode Go app doesn't understand …" — quit
   from the menu bar and Run again.
2. **Two companions at once.** The second can't bind port 8766 and the phone
   silently reaches the first. The menu bar says "Another copy of OpenCode
   Go is running" when this happens.
