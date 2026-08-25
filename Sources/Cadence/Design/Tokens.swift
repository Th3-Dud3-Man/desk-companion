import SwiftUI
import AppKit

// MARK: - Colour

extension NSColor {
    /// Builds a colour that resolves itself against the current appearance, so no
    /// view in the application has to know whether it is drawing light or dark.
    static func cadenceDynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(cadenceHex: isDark ? dark : light)
        }
    }

    convenience init(cadenceHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// The palette from docs/DESIGN-SYSTEM.md. Warm neutrals rather than blue-greys:
/// that single decision is most of what makes the application feel like paper on a
/// desk instead of a database front end.
enum Ink {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: .cadenceDynamic(light: light, dark: dark))
    }

    static let canvas        = dynamic(0xF6F5F1, 0x141513)
    static let surface       = dynamic(0xFFFFFF, 0x1C1E1B)
    static let surfaceSunken = dynamic(0xEFEEE9, 0x101210)
    static let surfaceHover  = dynamic(0xF2F1EC, 0x232522)
    static let sidebar       = dynamic(0xEFEEE8, 0x111210)

    static let hairline       = dynamic(0xE3E1D9, 0x2D2F2B)
    static let hairlineStrong = dynamic(0xCFCCC2, 0x3D403A)

    static let textPrimary   = dynamic(0x1B1C19, 0xEFEEE7)
    static let textSecondary = dynamic(0x61625C, 0xA1A299)
    static let textTertiary  = dynamic(0x93948C, 0x6D6E66)
    static let textOnAccent  = dynamic(0xFFFFFF, 0x0E1A15)

    static let accent      = dynamic(0x2E6B57, 0x63B899)
    static let accentHover = dynamic(0x265B4A, 0x77C7AA)
    static let accentSoft  = dynamic(0xE3EDE8, 0x1D3229)

    static let warning     = dynamic(0x8F6414, 0xD5A257)
    static let warningSoft = dynamic(0xF6EDD9, 0x33291A)

    static let danger     = dynamic(0xA34129, 0xE08268)
    static let dangerSoft = dynamic(0xF7E4DE, 0x35201C)

    static let neutralSoft = dynamic(0xECEAE3, 0x262824)

    /// Eight tints for patient monograms, all tested against both grounds.
    static let monogramTints: [Color] = [
        dynamic(0x2E6B57, 0x63B899),   // sage
        dynamic(0x3F6280, 0x7FAFD4),   // slate blue
        dynamic(0x8A5A2B, 0xD3A06A),   // amber
        dynamic(0x7A4A63, 0xC792AE),   // plum
        dynamic(0x4A6B33, 0x9CC46F),   // olive
        dynamic(0x8A4235, 0xD98D79),   // clay
        dynamic(0x3E6A6A, 0x74BFBF),   // teal
        dynamic(0x5B5A86, 0xA3A1D9),   // iris
    ]

    static func monogramTint(seed: Int) -> Color {
        monogramTints[abs(seed) % monogramTints.count]
    }
}

// MARK: - Typography

/// Two rules govern every piece of text: the size comes from this scale, and
/// anything numeric uses tabular figures so columns line up.
enum Typo {
    static let display     = Font.system(size: 26, weight: .semibold)
    static let title       = Font.system(size: 19, weight: .semibold)
    static let heading     = Font.system(size: 15, weight: .semibold)
    static let body        = Font.system(size: 13, weight: .regular)
    static let bodyStrong  = Font.system(size: 13, weight: .medium)
    static let caption     = Font.system(size: 11.5, weight: .regular)
    static let captionStrong = Font.system(size: 11.5, weight: .medium)
    static let label       = Font.system(size: 10.5, weight: .semibold)

    static let displayNumeric = Font.system(size: 26, weight: .semibold).monospacedDigit()
    static let titleNumeric   = Font.system(size: 19, weight: .semibold).monospacedDigit()
    static let headingNumeric = Font.system(size: 15, weight: .semibold).monospacedDigit()
    static let bodyNumeric    = Font.system(size: 13, weight: .regular).monospacedDigit()
    static let bodyStrongNumeric = Font.system(size: 13, weight: .medium).monospacedDigit()
    static let captionNumeric = Font.system(size: 11.5, weight: .regular).monospacedDigit()

    /// Section headers: small, uppercase, widely tracked.
    static let sectionLabel = Font.system(size: 10.5, weight: .semibold)
}

// MARK: - Metrics

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
    static let huge: CGFloat = 32
    static let giant: CGFloat = 40
}

enum Radius {
    static let chip: CGFloat = 5
    static let control: CGFloat = 7
    static let card: CGFloat = 10
    static let panel: CGFloat = 14
    static let sheet: CGFloat = 18
}

enum Metrics {
    /// Height of a consultation row at rest.
    static let rowHeight: CGFloat = 44
    /// Width of the time gutter on the day rail.
    static let timeGutter: CGFloat = 58
    static let sidebarWidth: CGFloat = 208
    static let inspectorWidth: CGFloat = 268
    static let controlHeight: CGFloat = 28
    static let smallControlHeight: CGFloat = 22
    static let largeControlHeight: CGFloat = 34
    /// Smallest usable window; every view is laid out to survive it.
    static let minimumWindow = CGSize(width: 880, height: 560)
    static let preferredWindow = CGSize(width: 1180, height: 760)
}

// MARK: - Motion

/// Short, functional animations. Every one of them collapses to nothing when the
/// system's "Reduce motion" setting is on.
enum Motion {
    static let instant = Animation.easeOut(duration: 0.09)
    static let quick = Animation.easeOut(duration: 0.14)
    static let standard = Animation.easeOut(duration: 0.20)
    static let entrance = Animation.spring(response: 0.32, dampingFraction: 0.86)

    static func respectful(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Depth

extension View {
    /// Level 1: a hairline. The default for anything sitting in the page.
    func cadenceHairline(_ radius: CGFloat = Radius.card, colour: Color = Ink.hairline) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(colour, lineWidth: 1)
        )
    }

    /// Level 3: genuinely floating — popovers, the command palette, toasts.
    func cadenceFloating(_ radius: CGFloat = Radius.panel) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Ink.surface)
                .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
                .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
        )
        .cadenceHairline(radius)
    }

    /// A card: surface, hairline, rounded.
    func cadenceCard(padding: CGFloat = Space.lg, radius: CGFloat = Radius.card) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Ink.surface))
            .cadenceHairline(radius)
    }

    /// Keyboard focus ring, drawn only for keyboard focus — never for the mouse.
    func cadenceFocusRing(_ isFocused: Bool, radius: CGFloat = Radius.control) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius + 1.5, style: .continuous)
                .strokeBorder(Ink.accent.opacity(isFocused ? 0.45 : 0), lineWidth: 3)
                .padding(-1.5)
        )
    }
}
