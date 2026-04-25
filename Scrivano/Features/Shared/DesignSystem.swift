import SwiftUI

// MARK: - Color Palette
extension Color {
    // Backgrounds
    static let appBg        = Color(hex: "#03080f")
    static let phoneBg      = Color(hex: "#060e1e")
    static let sheetBg      = Color(hex: "#081221")
    static let cardBg       = Color(hex: "#060e1e").opacity(0.9)

    // Brand
    static let brandBlue    = Color(hex: "#1e8ae0")
    static let brandCyan    = Color(hex: "#38d9f5")
    static let brandNavy    = Color(hex: "#114477")

    // Stage colors
    static let stageMedia   = Color(hex: "#ec4899")   // pink
    static let stageText    = Color(hex: "#eab308")   // yellow
    static let stageNotes   = Color(hex: "#22c55e")   // green
    static let stageWeb     = Color(hex: "#38d9f5")   // cyan

    // Text hierarchy
    static let textPrimary  = Color.white
    static let textSecondary = Color.white.opacity(0.75)
    static let textTertiary = Color.white.opacity(0.5)
    static let textQuaternary = Color.white.opacity(0.35)

    // Semantic
    static let danger       = Color(hex: "#f87171")
    static let success      = Color(hex: "#22c55e")

    // Borders
    static let borderDefault = Color.white.opacity(0.1)
    static let borderSubtle  = Color.white.opacity(0.07)
    static let borderBlue    = Color(hex: "#1e8ae0").opacity(0.28)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}

// MARK: - Typography
extension Font {
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Shared View Modifiers
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderDefault, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct BlueBorderCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [Color.brandBlue.opacity(0.18), Color.brandNavy.opacity(0.1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.borderBlue, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct PrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.inter(15, weight: .heavy))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#1e8ae0"), Color(hex: "#1060b0"), Color(hex: "#0a4d8e")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .shadow(color: Color.brandBlue.opacity(0.5), radius: 12, y: 6)
    }
}

struct SubBarStyle: ViewModifier {
    var accentColor: Color = .brandCyan
    func body(content: Content) -> some View {
        content
            .background(Color.phoneBg)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
            }
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
    func blueBorderCard() -> some View { modifier(BlueBorderCard()) }
    func primaryButtonStyle() -> some View { modifier(PrimaryButton()) }
}

// MARK: - Reusable Components

struct ScrivanoTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autoFocus: Bool = false

    @FocusState private var isFocused: Bool
    @State private var showText: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.inter(10, weight: .heavy))
                .foregroundColor(.textTertiary)
                .tracking(1)
                .textCase(.uppercase)

            ZStack(alignment: .trailing) {
                Group {
                    if isSecure && !showText {
                        SecureField(placeholder, text: $text)
                            .focused($isFocused)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(isSecure ? .default : keyboardType)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .focused($isFocused)
                    }
                }
                .font(.inter(14))
                .foregroundColor(.textPrimary)
                .padding(.leading, 16)
                .padding(.trailing, isSecure ? 44 : 16)
                .padding(.vertical, 13)

                if isSecure {
                    Button(action: { showText.toggle() }) {
                        Image(systemName: showText ? "eye" : "eye.slash")
                            .font(.system(size: 14))
                            .foregroundColor(Color.white.opacity(0.35))
                    }
                    .padding(.trailing, 14)
                }
            }
            .background(isFocused ? Color.brandBlue.opacity(0.10) : Color.white.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isFocused ? Color.brandCyan.opacity(0.7) : Color.white.opacity(0.12),
                        lineWidth: 1.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: isFocused ? Color.brandBlue.opacity(0.35) : .clear, radius: 10, x: 0, y: 0)
            .shadow(color: isFocused ? Color.brandCyan.opacity(0.12) : .clear, radius: 4, x: 0, y: 0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .onAppear {
                if autoFocus {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { isFocused = true }
                }
            }
        }
    }
}

struct SubScreenBar: View {
    let title: String
    var accentColor: Color = .brandCyan
    var backIcon: String = "chevron.left"
    var onBack: (() -> Void)?
    var trailingIcon: String? = nil
    var onTrailing: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { onBack?() }) {
                Image(systemName: backIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.07))
                    .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .clipShape(Circle())
            }

            Text(title)
                .font(.inter(16, weight: .heavy))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)

            if let icon = trailingIcon {
                Button(action: { onTrailing?() }) {
                    Text(icon)
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.07))
                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .clipShape(Circle())
                }
            } else {
                Spacer().frame(width: 36)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .modifier(SubBarStyle(accentColor: accentColor))
    }
}

struct TopGlowBar: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.brandCyan.opacity(0.6), Color.brandBlue.opacity(0.5), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

struct GoogleGIcon: View {
    var size: CGFloat = 16
    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let radius = sz.width * 0.35
            let lw = sz.width * 0.22

            func seg(_ start: Double, _ end: Double, _ hex: String) {
                var p = Path()
                p.addArc(center: c, radius: radius,
                         startAngle: .degrees(start), endAngle: .degrees(end),
                         clockwise: false)
                ctx.stroke(p, with: .color(Color(hex: hex)),
                           style: StrokeStyle(lineWidth: lw, lineCap: .butt))
            }

            // Blue: top arc from ~11 o'clock to ~2 o'clock (passes through 12/top)
            seg(240, 340, "#4285F4")
            // Red: left side going up
            seg(140, 240, "#EA4335")
            // Yellow: bottom-left
            seg(60, 140, "#FBBC05")
            // Green: lower-right
            seg(10, 60, "#34A853")

            // Horizontal bar (blue): center → right outer edge
            let barH = lw * 0.85
            var bar = Path()
            bar.addRect(CGRect(x: c.x, y: c.y - barH / 2,
                               width: radius + lw * 0.5, height: barH))
            ctx.fill(bar, with: .color(Color(hex: "#4285F4")))
        }
        .frame(width: size, height: size)
    }
}

struct ToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(icon: String, iconColor: Color, title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(icon)
                .font(.system(size: 18))
                .frame(width: 38, height: 38)
                .background(iconColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(iconColor.opacity(0.22), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.inter(14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                if let sub = subtitle {
                    Text(sub)
                        .font(.inter(11))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.brandBlue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct NavRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    var isDanger: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon)
                    .font(.system(size: 18))
                    .frame(width: 38, height: 38)
                    .background((isDanger ? Color.danger : iconColor).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke((isDanger ? Color.danger : iconColor).opacity(0.22), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.inter(14, weight: .semibold))
                        .foregroundColor(isDanger ? .danger : .textPrimary)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.inter(11))
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textQuaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.inter(10, weight: .heavy))
            .foregroundColor(.textQuaternary)
            .tracking(0.7)
            .textCase(.uppercase)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 4)
    }
}

struct LoadingOverlay: View {
    var message: String = "Loading…"
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(.brandCyan)
                    .scaleEffect(1.3)
                Text(message)
                    .font(.inter(13, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            .padding(28)
            .background(Color.sheetBg)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.borderDefault, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}
