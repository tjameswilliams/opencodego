import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Files staged for the next prompt, and the shrinking that makes sending
/// them from a phone reasonable.
///
/// Images are downscaled before they ever reach the wire. A 12MP photo is
/// ~4 MB that takes real time on cellular and buys nothing: vision models
/// see a resized copy anyway, so the long side is capped and the result
/// re-encoded as JPEG. What the user sees on screen is the thumbnail; what
/// travels is the transit copy.
@MainActor
final class PromptAttachments: ObservableObject {
    @Published private(set) var items: [Item] = []
    @Published var error: String?

    struct Item: Identifiable {
        let id = UUID().uuidString
        var name: String
        var mime: String
        var data: Data
        /// Rendered for the composer strip; nil for non-images.
        var thumbnail: UIImage?
    }

    /// Cap the long side at what vision models actually consume. Bigger is
    /// upload time spent on pixels the model discards.
    private static let maxDimension: CGFloat = 1568
    private static let jpegQuality: CGFloat = 0.8
    /// Matches the Mac's limit, checked here too so the failure lands
    /// before a long upload rather than after it.
    private static let totalLimit = 20 << 20

    var isEmpty: Bool { items.isEmpty }

    func add(image: UIImage, name: String = "image.jpg") {
        let scaled = Self.downscale(image)
        guard let data = scaled.jpegData(compressionQuality: Self.jpegQuality) else {
            error = "Couldn't prepare that image."
            return
        }
        append(Item(name: name, mime: "image/jpeg", data: data, thumbnail: scaled))
    }

    func add(fileAt url: URL) {
        // Security-scoped: files from the document picker live outside our
        // sandbox and the scope must be opened before reading.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't read \(url.lastPathComponent)."
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        if mime.hasPrefix("image/"), let image = UIImage(data: data) {
            add(image: image, name: url.lastPathComponent)
            return
        }
        append(Item(name: url.lastPathComponent, mime: mime, data: data, thumbnail: nil))
    }

    func load(_ selection: [PhotosPickerItem]) async {
        for item in selection {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { continue }
            add(image: image)
        }
    }

    func remove(_ id: String) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items.removeAll()
    }

    /// What goes on the wire.
    func wireAttachments() -> [Attachment] {
        items.map {
            Attachment(
                id: $0.id, name: $0.name, mime: $0.mime,
                data: $0.data.base64EncodedString()
            )
        }
    }

    private func append(_ item: Item) {
        let total = items.reduce(0) { $0 + $1.data.count } + item.data.count
        guard total <= Self.totalLimit else {
            error = "That would exceed the \(Self.totalLimit >> 20) MB limit for one message."
            return
        }
        items.append(item)
    }

    private static func downscale(_ image: UIImage) -> UIImage {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > maxDimension else { return image }
        let scale = maxDimension / longSide
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// The strip above the field: what's coming along, and a way to change your
/// mind about each one.
struct AttachmentStrip: View {
    @ObservedObject var attachments: PromptAttachments

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments.items) { item in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let thumbnail = item.thumbnail {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                VStack(spacing: 2) {
                                    Image(systemName: "doc")
                                        .font(.title3)
                                    Text(item.name)
                                        .font(.system(size: 9))
                                        .lineLimit(1)
                                        .padding(.horizontal, 4)
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.primary.opacity(0.06))
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Button {
                            attachments.remove(item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                        .accessibilityLabel("Remove \(item.name)")
                    }
                }
            }
            .padding(.top, 4)
            .padding(.trailing, 6)
        }
        .frame(height: 66)
    }
}
