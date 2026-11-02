import SwiftUI

// Mirrors the paper/ink palette of the review panel (DiffPanel) and the
// landing page, and dmg-resources/make_background.py for the install window.
enum SettingsTheme {
    static let paper = Color(red: 246 / 255, green: 239 / 255, blue: 216 / 255)
    static let card = Color(red: 251 / 255, green: 246 / 255, blue: 230 / 255)
    static let ink = Color(red: 32 / 255, green: 24 / 255, blue: 15 / 255)
    static let muted = Color(red: 138 / 255, green: 127 / 255, blue: 99 / 255)
    static let accent = Color(red: 179 / 255, green: 57 / 255, blue: 46 / 255)
    static let ruleSpacing: CGFloat = 31

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(SettingsTheme.mono(10, .bold))
            .tracking(1)
            .foregroundStyle(SettingsTheme.muted)
    }
}

// Ruled notebook paper, same as the landing page background.
struct RuledPaper: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SettingsTheme.paper))
            var y = SettingsTheme.ruleSpacing
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(SettingsTheme.accent.opacity(0.11)))
                y += SettingsTheme.ruleSpacing
            }
        }
        .ignoresSafeArea()
    }
}

// Ink segmented control, styled after the landing page language switch.
struct PillSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                option(title, value: value)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 3).fill(SettingsTheme.ink))
    }

    private func option(_ title: String, value: Value) -> some View {
        let selected = selection == value
        return Text(title)
            .font(SettingsTheme.mono(12, .bold))
            .foregroundStyle(selected ? SettingsTheme.ink : SettingsTheme.paper.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SettingsTheme.paper)
                        .matchedGeometryEffect(id: "highlight", in: highlight)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = value }
            }
    }
}

struct StyledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure = false

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)

            Group {
                if secure {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                }
            }
            .textFieldStyle(.plain)
            .font(SettingsTheme.mono(13))
            .foregroundStyle(SettingsTheme.ink)
            .tint(SettingsTheme.accent)
            .focused($focused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 2).fill(SettingsTheme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(focused ? SettingsTheme.accent : SettingsTheme.ink.opacity(0.3), lineWidth: focused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
        }
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(SettingsTheme.muted.opacity(0.7))
    }
}

// Flat, uppercase typewriter buttons matching the review panel's Accept/Cancel.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textCase(.uppercase)
            .font(SettingsTheme.mono(11, .bold))
            .tracking(0.6)
            .foregroundStyle(SettingsTheme.paper)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 2).fill(SettingsTheme.ink.opacity(configuration.isPressed ? 0.75 : 1)))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textCase(.uppercase)
            .font(SettingsTheme.mono(11, .bold))
            .tracking(0.6)
            .foregroundStyle(SettingsTheme.ink.opacity(configuration.isPressed ? 0.6 : 1))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(SettingsTheme.ink, lineWidth: 1))
            .contentShape(Rectangle())
    }
}
