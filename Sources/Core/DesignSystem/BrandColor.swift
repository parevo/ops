import SwiftUI
import AppKit

/// Semantic macOS colors — automatically adapt to light and dark appearance.
public enum BrandColor {
    public static var background: Color { Color(nsColor: .windowBackgroundColor) }
    public static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    public static var secondarySurface: Color { Color(nsColor: .underPageBackgroundColor) }
    public static var border: Color { Color(nsColor: .separatorColor) }

    public static let accent = Color.accentColor
    public static let success = Color(nsColor: .systemGreen)
    public static let warning = Color(nsColor: .systemOrange)
    public static let danger = Color(nsColor: .systemRed)
    public static let info = Color(nsColor: .systemBlue)

    public static var textPrimary: Color { Color(nsColor: .labelColor) }
    public static var textSecondary: Color { Color(nsColor: .secondaryLabelColor) }
    public static var textMuted: Color { Color(nsColor: .tertiaryLabelColor) }

    public static var consoleBackground: Color { Color(nsColor: .textBackgroundColor) }
    public static var consoleText: Color { Color(nsColor: .textColor) }
}
