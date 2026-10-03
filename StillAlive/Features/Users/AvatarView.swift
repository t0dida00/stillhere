import SwiftUI
import UIKit

/// A round photo, or initials on a color picked from `id` so each person keeps the same color.
struct AvatarView: View {
    let name: String
    let id: String
    var imageData: Data?
    var size: CGFloat = 40

    private static let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .mint, .red, .cyan]

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Self.palette[Int(PuzzleGenerator.seed(dayKey: id, slotIndex: 0) % UInt64(Self.palette.count))]
                    .overlay {
                        Text(Self.initials(of: name))
                            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// The first letter of the name, e.g. "Demo partner 2" → "D".
    static func initials(of name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    /// Shrinks a picked photo to a small square JPEG so it's cheap to store and, later, to sync.
    static func avatarData(from data: Data, side: CGFloat = 256) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = side / min(image.size.width, image.size.height)
        let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(x: (side - scaled.width) / 2, y: (side - scaled.height) / 2, width: scaled.width, height: scaled.height))
        }
    }
}
