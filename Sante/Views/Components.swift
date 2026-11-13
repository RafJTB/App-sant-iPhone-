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

// MARK: - Thème (app en blanc)

enum Theme {
    static let background = Color.white
    /// Fond des cartes et des lignes de liste : gris très clair légèrement vert.
    static let surface = Color(red: 0.957, green: 0.966, blue: 0.961)
    static let track = Color.black.opacity(0.07)
}

extension View {
    /// Listes et formulaires sur fond blanc.
    func whiteListStyle() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.background)
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
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(color)
                            .frame(width: geo.size.width * min(value / target, 1))
                    }
                }
                .frame(height: 6)
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

/// Anneau de progression (calories du jour).
struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Pastille de statut (verdict).
struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Date au-dessus du grand titre.
struct DateEyebrow: View {
    var body: some View {
        Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
