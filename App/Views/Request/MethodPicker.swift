import MinorRESTCore
import SwiftUI

/// Barva metody z assetů (`MethodGet` …), neznámá šedě.
func methodColor(_ method: String) -> Color {
    HTTPMethod.all.contains(method) ? Color("Method" + method.lowercased().capitalized) : .secondary
}

/// Výběr HTTP metody, text v barvě metody.
struct MethodPicker: View {
    @Binding var method: String
    @Environment(\.appFonts) private var fonts

    var body: some View {
        Menu {
            ForEach(HTTPMethod.all, id: \.self) { m in
                Button(m) { method = m }
            }
        } label: {
            Text(method).font(fonts.code.weight(.semibold)).foregroundStyle(methodColor(method))
        }
        .menuStyle(.button)
        .fixedSize()
    }
}
