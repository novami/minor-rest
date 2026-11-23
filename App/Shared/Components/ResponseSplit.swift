import AppKit
import SwiftUI

/// Svislý split request / odpověď s tažitelným děličem; výška spodního panelu je `height`
/// (ukládá se do workspace – `VSplitView` uloženou výšku neuplatní).
struct ResponseSplit<Top: View, Bottom: View>: View {
    @Binding var height: CGFloat
    var minHeight: CGFloat = 120
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom
    @State private var dragStart: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let maxHeight = max(minHeight, geo.size.height - minHeight - Self.divider)
            let h = min(max(height, minHeight), maxHeight)
            VStack(spacing: 0) {
                top.frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                    .padding(.vertical, (Self.divider - 1) / 2)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { g in
                            let start = dragStart ?? h
                            dragStart = start
                            height = min(max(start - g.translation.height, minHeight), maxHeight).rounded()
                        }
                        .onEnded { _ in dragStart = nil })
                bottom.frame(maxWidth: .infinity).frame(height: h)
            }
        }
    }

    static var divider: CGFloat { 5 }
}
