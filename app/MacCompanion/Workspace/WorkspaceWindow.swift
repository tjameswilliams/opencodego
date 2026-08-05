import RemoteKit
import SwiftUI

/// The desktop workspace's root. For now a proving ground: it connects the
/// shared stores to this Mac's own server over the loopback path and shows
/// what comes back, which exercises every layer the real three-pane
/// workspace will sit on — Wire handshake, LoopbackTrust, the stores, the
/// tokens. The panes replace this file's body as M2 lands.
struct WorkspaceWindow: View {
    @StateObject private var models = ModelStore(makeLink: { CompanionLink(target: .local(LoopbackTrust.key)) })
    @StateObject private var agents = AgentStore(makeLink: { CompanionLink(target: .local(LoopbackTrust.key)) })
    @StateObject private var commands = CommandStore(makeLink: { CompanionLink(target: .local(LoopbackTrust.key)) })

    var body: some View {
        VStack(spacing: 20) {
            BrandWordmark(height: 14, color: .inkMuted)
            if models.loading {
                ProgressView().controlSize(.small)
            } else if let error = models.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(Color.inkMuted)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(models.models.count) models", systemImage: "cpu")
                    Label("\(agents.agents.count) agents", systemImage: "person.crop.square")
                    Label("\(commands.commands.count) commands", systemImage: "command")
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(Color.ink)
            }
            Text("This Mac · loopback")
                .font(.footnote)
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .background(WindowAccessor { ActivationPolicy.shared.windowOpened($0) })
        .task {
            await models.loadIfNeeded()
            await agents.loadIfNeeded()
            await commands.loadIfNeeded()
        }
    }
}
