import SwiftUI

/// Shown after Log out. Every account's data stays on the device; pick one to log in, or create another.
struct LoggedOutView: View {
    @Environment(AccountStore.self) private var accounts

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("Log in").font(.largeTitle.bold())
                    Text("Choose an account on this iPhone. Check-in alarms and reminders are off until you log in.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(accounts.loginOptions) { account in
                        Button { accounts.logIn(account) } label: { row(account) }
                            .buttonStyle(.plain)
                    }
                }

                Button {
                    accounts.createAccount()
                } label: {
                    Label("Create new account", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(24)
            .padding(.top, 48)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(_ account: Account) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: account.displayName, id: account.publicID ?? account.key, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName).font(.headline)
                Text("ID: \(account.publicID ?? "")")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
    }
}
