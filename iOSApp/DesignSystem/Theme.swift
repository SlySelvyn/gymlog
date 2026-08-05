// Theme.swift — design system implemented from `GymLog Mockups.dc.html`.
// Tokens are taken verbatim from the mockups:
//   dark bg #0D0D0F · card rgba(28,28,30,0.75) r16 · accent #30D158
//   bright #5CE07E · on-accent #04230D · rest #FF9F0A · recording #FF453A
//   light derivation (F1): bg #F2F2F7 · white cards · accent #248A3D · rest #C93400
// Shared components: card style, scoreboard fonts, mic button, parsed chip,
// toast, waveform, equipment tag, stat card.

import SwiftUI
import GymLogCore

// MARK: - Colors (adaptive dark/light per mockups A1 vs F1)

enum GymTheme {

    static let background = adaptive(dark: UIColor(hex: 0x0D0D0F), light: UIColor(hex: 0xF2F2F7))
    static let cardFill = adaptive(dark: UIColor(hex: 0x1C1C1E, alpha: 0.75), light: .white)
    static let cardStroke = adaptive(dark: UIColor(white: 1, alpha: 0.06), light: UIColor(white: 0, alpha: 0.04))
    static let rowSeparator = adaptive(dark: UIColor(white: 1, alpha: 0.06), light: UIColor(hex: 0x3C3C43, alpha: 0.10))

    /// #30D158 dark · #248A3D light (mockup F1 uses the deeper green for contrast)
    static let accent = adaptive(dark: UIColor(hex: 0x30D158), light: UIColor(hex: 0x248A3D))
    /// Bright value color inside chips (#5CE07E); falls back to accent in light.
    static let accentBright = adaptive(dark: UIColor(hex: 0x5CE07E), light: UIColor(hex: 0x248A3D))
    /// Text/icon color ON accent surfaces (#04230D dark-green · white in light)
    static let onAccent = adaptive(dark: UIColor(hex: 0x04230D), light: .white)

    /// Rest timer — the one warm color (#FF9F0A · #C93400 in light)
    static let rest = adaptive(dark: UIColor(hex: 0xFF9F0A), light: UIColor(hex: 0xC93400))
    /// Recording / destructive (#FF453A both modes)
    static let recording = Color(UIColor(hex: 0xFF453A))

    static let textSecondary = Color.primary.opacity(0.6)
    static let textTertiary = Color.primary.opacity(0.4)
    static let textFaint = Color.primary.opacity(0.35)

    // Metrics
    static let cardRadius: CGFloat = 16
    static let micRadius: CGFloat = 18
    static let micHeight: CGFloat = 60
    static let currentGlow = Color(UIColor(hex: 0x30D158)).opacity(0.08)

    // MARK: helpers

    private static func adaptive(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Typography (scoreboard style)

extension Font {
    /// 17pt semibold mono — set rows: "225 lb × 5"
    static let scoreboard = Font.system(size: 17, weight: .semibold, design: .monospaced)
    /// 14pt mono — header timers
    static let timer = Font.system(size: 14, weight: .semibold, design: .monospaced)
    /// 22pt bold mono — stat card numbers
    static let statValue = Font.system(size: 22, weight: .bold, design: .monospaced)
    /// 12pt mono — rest seconds, meta
    static let metaMono = Font.system(size: 12, weight: .regular, design: .monospaced)
    /// 15pt bold mono — toast / chip values
    static let chipMono = Font.system(size: 15, weight: .bold, design: .monospaced)
}

// MARK: - Card style

struct GymCard: ViewModifier {
    var isCurrent = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: GymTheme.cardRadius, style: .continuous)
                    .fill(GymTheme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: GymTheme.cardRadius, style: .continuous)
                            .strokeBorder(isCurrent ? GymTheme.accent.opacity(0.55) : GymTheme.cardStroke,
                                          lineWidth: isCurrent ? 1.5 : 1)
                    )
                    .shadow(color: isCurrent ? GymTheme.currentGlow : .clear, radius: 12)
            )
    }
}

extension View {
    func gymCard(isCurrent: Bool = false) -> some View {
        modifier(GymCard(isCurrent: isCurrent))
    }
}

// MARK: - Equipment tag chip

struct EquipmentTag: View {
    let equipment: EquipmentType

    var body: some View {
        Text(equipment.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(GymTheme.textSecondary)
            .padding(.horizontal, 9).padding(.vertical, 2.5)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

// MARK: - Timer label (clock / hourglass)

struct TimerLabel: View {
    enum Kind { case session, rest }
    let kind: Kind
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind == .session ? "clock" : "hourglass")
                .font(.system(size: 12, weight: .medium))
            Text(text)
        }
        .font(.timer)
        .fontWeight(kind == .rest ? .bold : .semibold)
        .foregroundStyle(kind == .rest ? GymTheme.rest : GymTheme.textSecondary)
    }
}

// MARK: - Accent capsule button ("Finish", "Start", "Log it", "Try again")

struct AccentCapsuleButtonStyle: ButtonStyle {
    var height: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(GymTheme.onAccent)
            .padding(.horizontal, 18)
            .frame(height: height)
            .background(Capsule().fill(GymTheme.accent))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct BorderedCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(Capsule().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Hold-to-log mic button (idle green / pressed red, per component sheet)

struct HoldToLogMicButton: View {
    var isListening = false
    var label: String { isListening ? "Listening…" : "Hold to log set" }
    let onActivate: () -> Void

    @GestureState private var pressing = false

    var body: some View {
        let active = pressing || isListening
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 20, weight: .semibold))
            Text(label)
                .font(.system(size: 17, weight: .bold))
        }
        .foregroundStyle(active ? .white : GymTheme.onAccent)
        .frame(maxWidth: .infinity)
        .frame(height: GymTheme.micHeight)
        .background(
            RoundedRectangle(cornerRadius: GymTheme.micRadius, style: .continuous)
                .fill(active ? GymTheme.recording : GymTheme.accent)
                .shadow(color: (active ? GymTheme.recording : GymTheme.accent).opacity(0.25),
                        radius: 10, y: 6)
        )
        .scaleEffect(active ? 0.965 : 1)
        .animation(.snappy(duration: 0.15), value: active)
        .gesture(
            LongPressGesture(minimumDuration: 0.15)
                .updating($pressing) { value, state, _ in state = value }
                .onEnded { _ in onActivate() }
        )
        .accessibilityLabel("Hold to log a set by voice")
    }
}

// MARK: - Parsed-set chip (gradient capsule, mono values — component sheet)

struct ParsedChipView: View {
    let title: String
    let draft: SetDraft
    var emphasized = true       // accent border+tint; false = neutral variant (B3)
    var missingReps = false     // B5: dashed "? reps"

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
            if let w = draft.weight, w > 0 {
                dot
                Text("\(Self.trim(w)) \(draft.unit?.rawValue ?? "lb")")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
            }
            if let r = draft.reps {
                dot
                Text("\(r) reps")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
            } else if missingReps {
                dot
                Text("? reps")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.3))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(GymTheme.rest.opacity(0.7))
                            .frame(height: 2)
                            .offset(y: 3)
                            .mask(DashedLine())
                    }
            }
            if let rpe = draft.rpe {
                dot
                Text("RPE \(Self.trim(rpe))")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GymTheme.textSecondary)
            }
            if let rir = draft.rir {
                dot
                Text("RIR \(rir)")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GymTheme.textSecondary)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
        .background(
            Capsule()
                .fill(emphasized
                      ? AnyShapeStyle(LinearGradient(
                            colors: [GymTheme.accent.opacity(0.16), GymTheme.accent.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.clear))
                .overlay(Capsule().strokeBorder(
                    emphasized ? GymTheme.accent.opacity(0.6) : Color.primary.opacity(0.16),
                    lineWidth: 1.5))
                .shadow(color: emphasized ? GymTheme.accent.opacity(0.15) : .clear, radius: 16, y: 8)
        )
    }

    private var dot: some View {
        Circle().fill(Color.primary.opacity(0.35)).frame(width: 4, height: 4)
    }
    private var valueColor: Color { emphasized ? GymTheme.accentBright : GymTheme.textSecondary }

    static func trim(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(v)
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0
        while x < rect.width {
            p.addRect(CGRect(x: x, y: 0, width: 4, height: rect.height))
            x += 7
        }
        return p
    }
}

// MARK: - Confirmation toast (checkmark circle + mono label)

struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(GymTheme.accent).frame(width: 17, height: 17)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(GymTheme.onAccent)
            }
            Text(text)
                .font(.chipMono)
                .lineLimit(1)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(GymTheme.accent.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
        )
    }
}

// MARK: - Animated waveform (5px bars, staggered scaleY)

struct WaveformView: View {
    var barCount = 12
    var maxHeight: CGFloat = 60
    @State private var animating = false

    private let baseHeights: [CGFloat] = [0.3, 0.55, 0.85, 0.65, 1.0, 0.7, 0.9, 0.5, 0.75, 0.4, 0.6, 0.35]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i % 4 == 2 ? GymTheme.accentBright : GymTheme.accent)
                    .frame(width: 5, height: maxHeight * baseHeights[i % baseHeights.count])
                    .scaleEffect(y: animating ? 1 : 0.25, anchor: .center)
                    .animation(.easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.07),
                        value: animating)
            }
        }
        .frame(height: maxHeight)
        .onAppear { animating = true }
    }
}

// MARK: - Stat card (22pt mono value + muted unit + label)

struct StatCardView: View {
    let value: String
    var unit: String? = nil
    let label: String
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.statValue)
                    .foregroundStyle(dimmed ? Color.primary.opacity(0.25) : .primary)
                if let unit {
                    Text(unit)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(GymTheme.textTertiary)
                }
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(GymTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .gymCard()
    }
}
