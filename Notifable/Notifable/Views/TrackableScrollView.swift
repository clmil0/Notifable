import SwiftUI

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TrackableScrollView<Content: View>: View {
    let content: () -> Content
    @Binding var scrollOffset: CGFloat
    
    init(scrollOffset: Binding<CGFloat>, @ViewBuilder content: @escaping () -> Content) {
        self._scrollOffset = scrollOffset
        self.content = content
    }
    
    var body: some View {
        ScrollView {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: geo.frame(in: .global).minY
                            )
                    }
                )
        }
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            // Guardamos el valor global
            self.scrollOffset = value
        }
    }
}
