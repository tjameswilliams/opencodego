import RemoteKit
import Foundation

/// The menu bar's answer to "is the phone connected right now?" — one place,
/// reported into by every connection, so the UI never disagrees with itself.
@MainActor
final class PhoneLinkMonitor: ObservableObject {
    static let shared = PhoneLinkMonitor()

    @Published private(set) var connectedName: String?
    @Published private(set) var lastSeen: Date?

    func noteAuthenticated(name: String) {
        connectedName = name
        lastSeen = Date()
    }

    func noteDisconnected() {
        connectedName = nil
        lastSeen = Date()
    }
}
