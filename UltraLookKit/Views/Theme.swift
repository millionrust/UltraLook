import AppKit
import SwiftUI

enum Theme {
    static let accent = Color(nsColor: CodeTheme.dynamic(light: 0xE0512B, dark: 0xF0663F))
    static let background = Color(nsColor: CodeTheme.dynamic(light: 0xFFFFFF, dark: 0x1C1C1E))
    static let barBackground = Color(nsColor: CodeTheme.dynamic(light: 0xFAFAFA, dark: 0x222224))
    static let hairline = Color(nsColor: CodeTheme.dynamic(light: 0xE8E8EA, dark: 0x333336))
    static let badgeBorder = Color(nsColor: CodeTheme.dynamic(light: 0xDADADD, dark: 0x3E3E42))
    static let codeBlockBackground = Color(nsColor: CodeTheme.dynamic(light: 0xF6F6F7, dark: 0x262628))
    static let inlineCodeBackground = Color(nsColor: CodeTheme.dynamic(light: 0xEFEFF1, dark: 0x303033))
    static let selectedRow = Color(nsColor: CodeTheme.dynamic(light: 0xF2F2F4, dark: 0x2A2A2D))
    static let quoteBar = Color(nsColor: CodeTheme.dynamic(light: 0xDADADD, dark: 0x48484C))
    static let iconTile = Color(nsColor: CodeTheme.dynamic(light: 0xF2F2F4, dark: 0x2C2C2E))
    static let folder = Color(nsColor: CodeTheme.dynamic(light: 0x5AA9E6, dark: 0x6CB6EE))

    static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let codeLineSpacing: CGFloat = 3.5
}

/// The thin strip under the header: icon + title on the left, controls on the right.
struct SectionBar<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(Theme.barBackground)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
    }
}

/// Small pill-shaped toggle used for "Wrap" and the Preview/Raw switch.
struct PillButton: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 20)
                .background(Capsule().fill(isOn ? Theme.accent : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
