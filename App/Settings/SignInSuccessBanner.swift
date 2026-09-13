import SwiftUI
import StatusUI

/// Outside the scrolling accounts list so completion stays visible even when
/// the person left that list scrolled down or closed settings while signing in.
struct SignInSuccessBanner: View {
    @ObservedObject var login: LoginController
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        if let account = login.successNotice {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 17))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(loc("Signed in successfully"))
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("\(account.provider.title) · \(account.lastKnownName)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Button { login.dismissSuccessNotice() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(loc("Dismiss"))
                .help(loc("Dismiss"))
            }
            .padding(12)
            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            // Both vertical edges, not just the top. This sits in the detail
            // view's top safe area, and the bottom of that area is where the
            // scrolling content begins — macOS draws its edge separator on that
            // line. With padding on the top alone the box was pressed against
            // that line: twelve points of air above it and none below.
            // Horizontally twenty, which is what the pane behind it uses, so the
            // banner and the heading under it share one left edge.
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }
}
