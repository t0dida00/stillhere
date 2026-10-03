import SwiftUI

/// Shown over the app on a cold start: a thumbs-up ("I'm okay") springs up and bounces twice
/// with ripples, a heartbeat line draws across, and the name fades in. With Reduce Motion it's
/// a still version.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbUp = false
    @State private var bounces = 0
    @State private var ripple = false
    @State private var lineProgress: CGFloat = 0
    @State private var showName = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    // Ripples spreading out from the thumb as it bounces.
                    ForEach(0..<2) { index in
                        Circle()
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 2)
                            .frame(width: 96, height: 96)
                            .scaleEffect(ripple ? 2.1 : 1)
                            .opacity(ripple ? 0 : 0.8)
                            .animation(reduceMotion ? nil : .easeOut(duration: 1.1).delay(Double(index) * 0.45), value: ripple)
                    }
                    Image(systemName: "hand.thumbsup.circle.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.bounce, value: bounces)
                        // Raised like a thumb: from small and tilted back to upright.
                        .scaleEffect(thumbUp ? 1 : 0.4)
                        .rotationEffect(.degrees(thumbUp ? 0 : -35))
                        .opacity(thumbUp ? 1 : 0)
                }
                .frame(height: 200)

                HeartbeatLine()
                    .trim(from: 0, to: lineProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 220, height: 44)

                Text(verbatim: "Still Here")
                    .font(.largeTitle.bold())
                    .opacity(showName ? 1 : 0)
                    .offset(y: showName ? 0 : 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Still Here"))
        .task { await play() }
    }

    private func play() async {
        guard !reduceMotion else {
            thumbUp = true
            lineProgress = 1
            showName = true
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { thumbUp = true }
        withAnimation(.easeInOut(duration: 1.0).delay(0.15)) { lineProgress = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(0.55)) { showName = true }
        try? await Task.sleep(for: .milliseconds(380))
        ripple = true
        // Two bounces once it's up.
        for _ in 0..<2 {
            bounces += 1
            try? await Task.sleep(for: .milliseconds(380))
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
