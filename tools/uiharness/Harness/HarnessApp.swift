import GoKit
import SwiftUI

@main
struct HarnessApp: App {
    var body: some Scene { WindowGroup { HarnessView() } }
}

struct HarnessView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 28) {
                Group {
                    label("Nav lockup — full at 15")
                    BrandWordmark(height: 15)
                    label("Nav lockup — full at 12")
                    BrandWordmark(height: 12)
                    label("Compact at 15")
                    BrandWordmark(height: 15, text: BrandWordmark.compact)
                    label("Launch lockup at 30")
                    BrandWordmark(height: 30)
                }
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { BrandWordmark(height: 15) }
                ToolbarItem(placement: .topBarTrailing) {
                    Circle().fill(.green).frame(width: 10, height: 10)
                }
            }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(Color.inkMuted)
    }
}
