import SwiftUI

/// Modo "una por una": la misma tarjeta de la Bandeja, pero de a un comercio,
/// avanzando sola al aplicar. Es el atajo para vaciar la Bandeja de una sentada
/// en vez de ir bajando por la lista.
struct ClassifyFlowView: View {

    let groups: [InboxGroup]
    let suggestion: (InboxGroup) -> CategorySuggestion?
    let frequentCategories: (CategorySuggestion?) -> [String]
    var onPick: (InboxGroup, String) -> Void
    var onOther: (InboxGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("isDarkMode") private var isDarkMode = true

    @State private var index = 0

    private var palette: Palette { Palette(scheme) }

    private var current: InboxGroup? {
        groups.indices.contains(index) ? groups[index] : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let current {
                    Text("\(index + 1) de \(groups.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondaryLabel)

                    let hint = suggestion(current)
                    InboxMerchantCard(
                        group: current,
                        suggestion: hint,
                        frequentCategories: frequentCategories(hint),
                        isExpanded: true,
                        isHighlighted: false,
                        onToggle: {},
                        onPick: { category in
                            onPick(current, category)
                            advance()
                        },
                        onOther: { onOther(current) }
                    )

                    Button("Saltar por ahora") { advance() }
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryLabel)

                    Spacer()
                } else {
                    ContentUnavailableView("Bandeja vacía",
                                           systemImage: "checkmark.circle.fill",
                                           description: Text("No queda ningún comercio por clasificar."))
                }
            }
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.background)
            .navigationTitle("Clasificar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if index + 1 >= groups.count {
                dismiss()
            } else {
                index += 1
            }
        }
    }
}
