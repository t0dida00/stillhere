import Foundation

/// A way for partners to reach me when I miss check-ins. Up to `maxCount` per user, any mix of kinds.
struct EmergencyContact: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case phone, zalo, whatsApp, telegram

        var id: String { rawValue }

        var title: String {
            switch self {
            case .phone: String(localized: "Phone")
            case .zalo: "Zalo"
            case .whatsApp: "WhatsApp"
            case .telegram: "Telegram"
            }
        }

        /// For menus, which can only show SF Symbols; rows use `ContactAppIcon`.
        var symbol: String {
            switch self {
            case .phone: "phone.fill"
            case .zalo: "z.square.fill"
            case .whatsApp: "phone.bubble.fill"
            case .telegram: "paperplane.fill"
            }
        }
    }

    static let maxCount = PlanLimits.emergencyContacts

    var id = UUID()
    var kind: Kind
    var value: String

    /// Opens the contact in the right app: a call, or a chat in Zalo, WhatsApp or Telegram.
    var url: URL? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        switch kind {
        case .phone:
            let dialable = (trimmed.hasPrefix("+") ? "+" : "") + digits
            return digits.isEmpty ? nil : URL(string: "tel:\(dialable)")
        case .zalo:
            return digits.isEmpty ? nil : URL(string: "https://zalo.me/\(digits)")
        case .whatsApp:
            return digits.isEmpty ? nil : URL(string: "https://wa.me/\(digits)")
        case .telegram:
            // A username (@name or name) or a phone number.
            let username = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
            if username.isEmpty { return nil }
            if username.allSatisfy({ $0.isNumber || $0 == "+" || $0 == " " }) {
                return URL(string: "https://t.me/+\(digits)")
            }
            return URL(string: "https://t.me/\(username)")
        }
    }
}
