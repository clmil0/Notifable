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
    @Binding var scrollToTopTrigger: Bool
    
    init(scrollOffset: Binding<CGFloat>, scrollToTopTrigger: Binding<Bool> = .constant(false), @ViewBuilder content: @escaping () -> Content) {
        self._scrollOffset = scrollOffset
        self._scrollToTopTrigger = scrollToTopTrigger
        self.content = content
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("top")
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
            }
            .onChange(of: scrollToTopTrigger) { _, _ in
                withAnimation {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                self.scrollOffset = value
            }
        }
    }
}
