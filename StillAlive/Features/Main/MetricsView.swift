import SwiftUI

struct MetricsView: View {
    let metrics: Metrics

    var body: some View {
        HStack(spacing: 12) {
            tile("Checked in", value: "\(metrics.checkedInDays)", unit: metrics.checkedInDays == 1 ? "day" : "days", color: .green)
            tile("Streak", value: "\(metrics.currentStreak)", unit: metrics.currentStreak == 1 ? "day" : "days", color: .accentColor)
            tile("Missed", value: "\(metrics.missedCount)", unit: "check-ins", color: .red)
        }
    }

    private func tile(_ title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold())
                .foregroundStyle(color)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
