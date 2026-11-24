import SwiftUI

/// Prázdný stav panelu: titulek a volitelná nápověda, vycentrované.
struct EmptyState: View {
    let title: String
    var hint: String?
    @Environment(\.appFonts) private var fonts

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
            if let hint {
                Text(hint).font(fonts.small).opacity(0.8)
            }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
