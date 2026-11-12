import SwiftUI

// MARK: - Formatage

enum Fmt {
    static func kcal(_ v: Double) -> String {
        Int(v.rounded()).formatted()
    }

    static func grams(_ v: Double) -> String {
        "\(Int(v.rounded())) g"
    }

    static func signed(_ v: Double, digits: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(digits)).sign(strategy: .always()))
    }

    static func number(_ v: Double, digits: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func duration(_ t: TimeInterval) -> String {
        let minutes = Int((t / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return String(format: "%d h %02d", h, m)
    }

    static func time(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }

    static func shortDay(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

// MARK: - Composants

struct Card<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatTile: View {
    let value: String
    let unit: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                Text(unit).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Barre de progression d'un macro-nutriment.
struct MacroBar: View {
    let label: String
    let value: Double
    let target: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                if let target {
                    Text("\(Fmt.grams(value)) / \(Fmt.grams(target))")
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(Fmt.grams(value)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let target, target > 0 {
                ProgressView(value: min(value, target), total: target).tint(color)
            }
        }
    }
}

struct MacroSummaryRows: View {
    let macros: Macros

    var body: some View {
        LabeledContent("Calories", value: "\(Fmt.kcal(macros.kcal)) kcal")
        LabeledContent("Protéines", value: Fmt.grams(macros.protein))
        LabeledContent("Glucides", value: Fmt.grams(macros.carbs))
        LabeledContent("Lipides", value: Fmt.grams(macros.fat))
    }
}

struct EmptyHealthHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
