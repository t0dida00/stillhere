import SwiftData
import SwiftUI

struct CheckInView: View {
    let slotKey: SlotKey

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]
    @State private var input = ""
    @State private var wrongAttempts = 0
    @State private var solved = false
    @State private var dragOffset: CGFloat = 0

    private var puzzle: Puzzle {
        PuzzleGenerator.puzzle(dayKey: slotKey.dayKey, slotIndex: slotKey.slotIndex, difficulty: settings.first?.difficulty ?? 1)
    }

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Still alive?")
                    .font(.largeTitle.bold())
                Text("Solve this to check in.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(puzzle.question)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .modifier(ShakeEffect(animatableData: CGFloat(wrongAttempts)))

            Text(input.isEmpty ? " " : input)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Your answer: \(input)")

            Spacer()

            Keypad(input: $input, onSubmit: submit)

            Button("Skip this check-in", role: .destructive, action: skip)
                .padding(.top, 4)
        }
        .padding()
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { dragOffset = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 150 {
                        skip()
                    } else {
                        withAnimation(.spring) { dragOffset = 0 }
                    }
                }
        )
        .sensoryFeedback(.success, trigger: solved)
        .sensoryFeedback(.error, trigger: wrongAttempts)
    }

    private func submit() {
        guard Int(input) == puzzle.answer else {
            withAnimation(.default) { wrongAttempts += 1 }
            input = ""
            return
        }
        solved = true
        CheckInService(context: context).checkIn(slotKey)
        dismiss()
    }

    /// Skip button and swipe-down both record `skipped`.
    private func skip() {
        CheckInService(context: context).skip(slotKey)
        dismiss()
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}
