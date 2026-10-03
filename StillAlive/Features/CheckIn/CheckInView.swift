import SwiftData
import SwiftUI

/// The puzzle. For a scheduled slot it records checked in or skipped; for a partner's request,
/// solving it answers the request and "Not now" sets it aside.
struct CheckInView: View {
    let target: CheckInTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [AppSettings]
    @State private var input = ""
    @State private var wrongAttempts = 0
    @State private var solved = false
    @State private var dragOffset: CGFloat = 0

    private var puzzle: Puzzle {
        let difficulty = settings.first?.difficulty ?? 1
        switch target {
        case .slot(let key):
            return PuzzleGenerator.puzzle(dayKey: key.dayKey, slotIndex: key.slotIndex, difficulty: difficulty)
        case .request(let id, _):
            return PuzzleGenerator.puzzle(dayKey: id, slotIndex: 0, difficulty: difficulty)
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                switch target {
                case .slot:
                    Text("Still here?")
                        .font(.largeTitle.bold())
                    Text("Solve this to check in.")
                        .foregroundStyle(.secondary)
                case .request(_, let name):
                    Text("\(name) asked you to check in")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text("Solve this to let them know you're okay.")
                        .foregroundStyle(.secondary)
                }
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

            switch target {
            case .slot:
                Button("Skip this check-in", role: .destructive, action: skip)
                    .padding(.top, 4)
            case .request:
                Button("Not now", action: skip)
                    .padding(.top, 4)
            }
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
        switch target {
        case .slot(let key):
            CheckInService(context: context).checkIn(key)
        case .request:
            CheckInRequestService(context: context).answerAll()
        }
        dismiss()
    }

    /// Skip button and swipe-down: a slot is recorded `skipped`; a request is set aside.
    private func skip() {
        switch target {
        case .slot(let key):
            CheckInService(context: context).skip(key)
        case .request(let id, _):
            CheckInRequestService(context: context).dismiss(id: id)
        }
        dismiss()
    }
}

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}
