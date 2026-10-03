import SwiftUI

struct Keypad: View {
    @Binding var input: String
    var maxDigits = 4
    var onSubmit: () -> Void

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["delete", "0", "submit"]]

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button { tap(key) } label: { label(for: key) }
                            .buttonStyle(KeyStyle(prominent: key == "submit"))
                            .disabled(key == "submit" && input.isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func label(for key: String) -> some View {
        switch key {
        case "delete": Image(systemName: "delete.left").accessibilityLabel("Delete")
        case "submit": Image(systemName: "checkmark").accessibilityLabel("Submit answer")
        default: Text(key)
        }
    }

    private func tap(_ key: String) {
        switch key {
        case "delete": if !input.isEmpty { input.removeLast() }
        case "submit": onSubmit()
        default: if input.count < maxDigits { input += key }
        }
    }
}

private struct KeyStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
