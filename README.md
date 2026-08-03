# Go for OpenCode

Drive the [OpenCode](https://opencode.ai) coding agent on your Mac from a
native iPhone app — with **zero network configuration**. No Tailscale, no
VPS, no port forwarding, no IP addresses to type. Your Mac writes the code;
your phone holds the leash.

> **Status: early development.** Pairing, session browsing, prompting,
> streaming, and tool approvals work on LAN today; remote (hole-punched)
> access and push notifications are in active development.

*Go for OpenCode is an independent project, not affiliated with or endorsed by
the OpenCode project or Anomaly. It drives your own OpenCode installation.*

## How it works

```
iPhone (native SwiftUI)
   │  end-to-end encrypted (ChaChaPoly; Curve25519 pairing)
   │  Bonjour TCP on your LAN · hole-punched UDP from anywhere
   ▼
Mac menu-bar companion
   │  owns `opencode serve`, bound to localhost only
   ▼
OpenCode — your projects, your git, your model credentials. All on your Mac.
```

- **Pairing, not accounts.** The two devices exchange public keys through
  *your own* iCloud private database and confirm a 6-digit code shown on
  both screens. No third-party servers — not for pairing, not for traffic,
  not for notifications.
- **The OpenCode server never touches the network.** It listens on
  localhost; the companion is the only gateway, and every connection is
  authenticated and encrypted before a byte of protocol flows.
- **Answers outlive the socket.** iOS suspends network connections when you
  switch apps; the turn keeps running on the Mac, and the phone resumes the
  stream where it left off.
- **Approvals on your phone.** When the agent wants to run a command, you
  get the exact command and Allow Once / Always / Reject — then a per-file
  diff of what the turn changed.

## Install

Coming: `brew install --cask opencodego` (the app keeps itself up to date
via Sparkle). Until then, build from source:

```sh
brew install xcodegen opencode
cd app && xcodegen generate && open OpenCodeGo.xcodeproj
```

Run the **MacCompanion** target on your Mac and the **Phone** target on your
iPhone, then pair from the menu bar (both devices must be signed into the
same iCloud account).

## Repository layout

| Path | What |
|---|---|
| `packages/GoKit/` | Shared Swift package: transport, pairing, protocol v1, policy — unit-tested (`swift test`) |
| `app/MacCompanion/` | Menu-bar app: OpenCode lifecycle, version-skew adapter, Wire server |
| `app/Phone/` | SwiftUI iPhone app |
| `docs/protocol-v1.md` | The phone⇄Mac contract, with the verified OpenCode mapping behind it |
| `spikes/` | Throwaway validation scripts |
| `tools/uiharness/` | Renders the real phone views in the simulator without a paired Mac |

The transport and pairing stack is shared with (and battle-tested in)
[Tomte](https://tomteapp.com), the author's local-AI assistant for Mac + iPhone.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md) — use it, read it, change it,
share it, for any noncommercial purpose. Commercial use requires a separate
license; open an issue if that's you. Third-party notices are in
[NOTICE.md](NOTICE.md).
