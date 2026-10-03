import SwiftUI

/// Settings → FAQ: common questions, grouped by topic, searchable. Answers describe how the app
/// behaves today; plan numbers come from `PlanLimits`.
struct FAQView: View {
    @State private var search = ""

    private var sections: [FAQSection] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return FAQSection.all }
        return FAQSection.all.compactMap { section in
            let items = section.items.filter {
                $0.question.localizedCaseInsensitiveContains(query) || $0.answer.localizedCaseInsensitiveContains(query)
            }
            return items.isEmpty ? nil : FAQSection(title: section.title, items: items)
        }
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        DisclosureGroup {
                            Text(item.answer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } label: {
                            Text(item.question)
                                .font(.body.weight(.medium))
                        }
                    }
                }
            }
        }
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: Text("Search questions"))
        .navigationTitle("FAQ")
    }
}

private struct FAQItem: Identifiable {
    let question: String
    let answer: String
    var id: String { question }
}

private struct FAQSection: Identifiable {
    let title: String
    let items: [FAQItem]
    var id: String { title }

    static var all: [FAQSection] {
        [
            FAQSection(title: String(localized: "Check-ins"), items: [
                FAQItem(question: String(localized: "How does a check-in work?"),
                        answer: String(localized: "At each check-in time an alarm rings (or a notification on older iOS). Open it and solve a quick math puzzle. That's it: your partners can see you're okay. Reminders keep coming every few minutes until you check in or the grace window ends.")),
                FAQItem(question: String(localized: "What happens if I miss a check-in?"),
                        answer: String(localized: "If you don't check in before the grace window ends (1 hour by default), it counts as missed and shows red on your calendar. Your partners are notified of every missed check-in, and they can ask you to check in.")),
                FAQItem(question: String(localized: "What's the difference between skipping and missing?"),
                        answer: String(localized: "Skipping is a choice: you tapped Skip or swiped the puzzle away. It shows orange and still counts as a finished day, so your streak continues. Missing means nothing happened in time; it shows red and breaks your streak.")),
                FAQItem(question: String(localized: "Why didn't my alarm ring?"),
                        answer: String(localized: "Check that alarms and notifications are allowed for Still Here in the iOS Settings app, and that Still Here is allowed in your Focus modes. Alarms need iOS 26 or later; on older versions you get notifications instead. Opening the app once a day also keeps reminders up to date.")),
                FAQItem(question: String(localized: "Can I change my check-in time?"),
                        answer: String(localized: "Yes, in Settings → Check-in times. A new time applies today, unless it's earlier than a check-in you've already finished today; then it starts tomorrow. The free plan has \(PlanLimits.checkInTimes) check-in time a day.")),
            ]),
            FAQSection(title: String(localized: "Partners"), items: [
                FAQItem(question: String(localized: "How do I add a partner?"),
                        answer: String(localized: "On the Users tab, tap Add partner by code and type their invite code, or tap Scan QR code and scan theirs. You can also share your own invite from Users → Me. The free plan includes \(PlanLimits.partners) partner, counting invites you've sent.")),
                FAQItem(question: String(localized: "What happens when a partner misses a check-in?"),
                        answer: String(localized: "You get a notification, and it's saved on the Notifications tab. On their Check-In view, a red Request a check-in button appears: hold it for 3 seconds to ask them to check in.")),
                FAQItem(question: String(localized: "Can partners ask me to check in?"),
                        answer: String(localized: "Yes. When a partner asks, you get a notification and the puzzle opens as soon as you open the app. Solving it lets them know you're okay; Not now sets the request aside.")),
                FAQItem(question: String(localized: "What are emergency contacts?"),
                        answer: String(localized: "Ways for partners to reach you if you miss check-ins: phone, Zalo, WhatsApp or Telegram. Add up to \(PlanLimits.emergencyContacts) on the Users tab. To see a partner's contacts, press and hold their avatar on Check-In.")),
            ]),
            FAQSection(title: String(localized: "Privacy & data"), items: [
                FAQItem(question: String(localized: "Do I need an account?"),
                        answer: String(localized: "No. Still Here creates an invite code for you. It's kept in your iCloud Keychain, so it stays the same if you reinstall the app or move to a new iPhone.")),
                FAQItem(question: String(localized: "Who can see my location?"),
                        answer: String(localized: "Nobody, unless you turn Location on in Settings. Even then, only partners you choose with Share my location see it: where you checked in and where you last used the app. Your location is only read while the app is open.")),
                FAQItem(question: String(localized: "Does it work without internet?"),
                        answer: String(localized: "Yes. Check-ins, alarms and reminders work offline. Partner updates need a connection.")),
            ]),
            FAQSection(title: String(localized: "Plans"), items: [
                FAQItem(question: String(localized: "What does Premium include?"),
                        answer: String(localized: "Premium is coming soon. It will raise the free plan's limits: more partners, more emergency contacts and more check-in times a day.")),
            ]),
        ]
    }
}
