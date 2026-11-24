import SwiftUI

/// Krátká oznámení u spodního okraje okna.
struct ToastStack: View {
    let center: ToastCenter

    var body: some View {
        VStack(spacing: 6) {
            ForEach(center.items) { toast in
                Text(toast.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(toast.isError ? Color.red : Color.primary)
                    .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    .shadow(radius: 4, y: 1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.2), value: center.items.map(\.id))
        .allowsHitTesting(false)
    }
}
