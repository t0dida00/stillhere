import SwiftUI

/// Shown over the app on a cold start: the heart beats twice with ripples, a heartbeat line
/// draws across, and the name fades in. With Reduce Motion it's a still version.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var beat = false
    @State private var ripple = false
    @State private var lineProgress: CGFloat = 0
    @State private var showName = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    // Ripples spreading out from the heart on each beat.
                    ForEach(0..<2) { index in
                        Circle()
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 2)
                            .frame(width: 96, height: 96)
                            .scaleEffect(ripple ? 2.1 : 1)
                            .opacity(ripple ? 0 : 0.8)
                            .animation(reduceMotion ? nil : .easeOut(duration: 1.1).delay(Double(index) * 0.45), value: ripple)
                    }
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(Color.accentColor)
                        .scaleEffect(beat ? 1.12 : 1)
                }
                .frame(height: 200)

                HeartbeatLine()
                    .trim(from: 0, to: lineProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 220, height: 44)

                Text(verbatim: "StillAlive?")
                    .font(.largeTitle.bold())
                    .opacity(showName ? 1 : 0)
                    .offset(y: showName ? 0 : 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "StillAlive?"))
        .task { await play() }
    }

    private func play() async {
        guard !reduceMotion else {
            lineProgress = 1
            showName = true
            return
        }
        ripple = true
        withAnimation(.easeInOut(duration: 1.0)) { lineProgress = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) { showName = true }
        // Two quick beats, like a pulse: lub-dub.
        for _ in 0..<2 {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { beat = true }
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { beat = false }
            try? await Task.sleep(for: .milliseconds(300))
        }
    }
}

/// A flat line with one heartbeat spike in the middle.
private struct HeartbeatLine: Shape {
    func path(in rect: CGRect) -> Path {
        let midY = rect.midY
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))
        path.addLine(to: CGPoint(x: w * 0.30, y: midY))
        path.addLine(to: CGPoint(x: w * 0.36, y: midY - h * 0.12))
        path.addLine(to: CGPoint(x: w * 0.42, y: midY))
        path.addLine(to: CGPoint(x: w * 0.47, y: midY))
        path.addLine(to: CGPoint(x: w * 0.52, y: rect.minY))
        path.addLine(to: CGPoint(x: w * 0.58, y: rect.maxY))
        path.addLine(to: CGPoint(x: w * 0.63, y: midY))
        path.addLine(to: CGPoint(x: w * 0.70, y: midY - h * 0.15))
        path.addLine(to: CGPoint(x: w * 0.76, y: midY))
        path.addLine(to: CGPoint(x: w, y: midY))
        return path
    }
}
