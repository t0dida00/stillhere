import SwiftUI

/// Shown over the app on a cold start: three "I'm okay" signs slide past, thumbs-up, check mark,
/// then OK, each with a ripple; a heartbeat line draws across, and the name fades in. With
/// Reduce Motion it's a still version showing OK.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbUp = false
    /// Which sign is showing: 0 thumbs-up, 1 check mark, 2 OK.
    @State private var step = 0
    @State private var lineProgress: CGFloat = 0
    @State private var showName = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    // A fresh ripple each time a sign arrives.
                    if thumbUp && !reduceMotion {
                        RippleRings().id(step)
                    }
                    SplashSign(step: step)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        // The first sign is raised like a thumb: from small and tilted back to upright.
                        .scaleEffect(thumbUp ? 1 : 0.4)
                        .rotationEffect(.degrees(thumbUp ? 0 : -35))
                        .opacity(thumbUp ? 1 : 0)
                }
                .frame(width: 220)
                .clipped()
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
            step = SplashSign.count - 1
            lineProgress = 1
            showName = true
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { thumbUp = true }
        withAnimation(.easeInOut(duration: 1.4).delay(0.15)) { lineProgress = 1 }
        withAnimation(.easeOut(duration: 0.5).delay(1.2)) { showName = true }
        // Slide to the next sign while the previous one leaves to the left.
        for next in 1..<SplashSign.count {
            try? await Task.sleep(for: .milliseconds(560))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { step = next }
        }
    }

}

/// The splash's "I'm okay" signs, in order: thumbs-up, check mark, OK.
private struct SplashSign: View {
    static let count = 3
    let step: Int

    var body: some View {
        Group {
            switch step {
            case 0:
                Image(systemName: "hand.thumbsup.circle.fill")
                    .font(.system(size: 96))
            case 1:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 96))
            default:
                Circle()
                    .frame(width: 96, height: 96)
                    .overlay {
                        Text(verbatim: "OK")
                            .font(.system(size: 38, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(.systemBackground))
                    }
            }
        }
        .foregroundStyle(Color.accentColor)
        .frame(width: 110, height: 110)
    }
}

/// One ripple of two rings spreading out from the sign.
private struct RippleRings: View {
    @State private var spread = false

    var body: some View {
        ZStack {
            ForEach(0..<2) { index in
                Circle()
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 2)
                    .frame(width: 96, height: 96)
                    .scaleEffect(spread ? 2.0 : 1)
                    .opacity(spread ? 0 : 0.8)
                    .animation(.easeOut(duration: 0.9).delay(Double(index) * 0.25), value: spread)
            }
        }
        .onAppear { spread = true }
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
