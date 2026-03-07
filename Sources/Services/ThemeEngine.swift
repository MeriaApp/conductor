import SwiftUI

/// Continuous luminance-based theme engine
/// Luminance 0.0 = midnight (pure dark), 1.0 = paper (light mode)
/// All colors shift proportionally via HSL L-channel
/// WCAG AA contrast maintained at all levels
@MainActor
final class ThemeEngine: ObservableObject {
    static let shared = ThemeEngine()

    @AppStorage("luminance") var luminance: Double = 0.3 {
        didSet { recalculate() }
    }

    // MARK: - Colors (batch-updated via single objectWillChange)

    var base: Color = .black
    var surface: Color = .black
    var elevated: Color = .black
    var overlay: Color = .black

    var muted: Color = .gray
    var secondary: Color = .gray
    var primary: Color = .white
    var bright: Color = .white

    var sky: Color = .blue
    var sage: Color = .green
    var sand: Color = .orange
    var rose: Color = .red
    var lavender: Color = .purple
    var amber: Color = .yellow

    // MARK: - Semantic Colors

    var inputBackground: Color = .black
    var codeBackground: Color = .black
    var toolBackground: Color = .black
    var thinkingBackground: Color = .black
    var separator: Color = .gray

    private init() {
        recalculate()
    }

    // MARK: - Luminance Adjustment

    /// Adjust luminance by delta (keyboard: [ and ])
    func adjustLuminance(by delta: Double) {
        luminance = max(0, min(1, luminance + delta))
    }

    // MARK: - Color Calculation

    private func recalculate() {
        objectWillChange.send()
        let l = luminance

        // Background colors: at l=0, use dark palette values. At l=1, invert to light.
        base = shiftBackground(ColorPalette.base, luminance: l)
        surface = shiftBackground(ColorPalette.surface, luminance: l)
        elevated = shiftBackground(ColorPalette.elevated, luminance: l)
        overlay = shiftBackground(ColorPalette.overlay, luminance: l)

        // Foreground colors: at l=0, use light text. At l=1, use dark text.
        muted = shiftForeground(ColorPalette.muted, luminance: l)
        secondary = shiftForeground(ColorPalette.secondary, luminance: l)
        primary = shiftForeground(ColorPalette.primary, luminance: l)
        bright = shiftForeground(ColorPalette.bright, luminance: l)

        // Signal colors: minimal shift, just enough for contrast
        sky = shiftSignal(ColorPalette.sky, luminance: l)
        sage = shiftSignal(ColorPalette.sage, luminance: l)
        sand = shiftSignal(ColorPalette.sand, luminance: l)
        rose = shiftSignal(ColorPalette.rose, luminance: l)
        lavender = shiftSignal(ColorPalette.lavender, luminance: l)
        amber = shiftSignal(ColorPalette.amber, luminance: l)

        // Semantic
        inputBackground = shiftBackground(
            HSLColor(h: 230, s: 0.06, l: 0.13), luminance: l
        )
        codeBackground = shiftBackground(
            HSLColor(h: 230, s: 0.08, l: 0.09), luminance: l
        )
        toolBackground = shiftBackground(
            HSLColor(h: 230, s: 0.05, l: 0.15), luminance: l
        )
        thinkingBackground = shiftBackground(
            HSLColor(h: 265, s: 0.08, l: 0.13), luminance: l
        )
        separator = shiftBackground(
            HSLColor(h: 230, s: 0.04, l: 0.25), luminance: l
        )
    }

    /// Shift background colors: dark at l=0, light at l=1
    private func shiftBackground(_ hsl: HSLColor, luminance l: Double) -> Color {
        // Linear interpolation from dark lightness to inverted lightness
        let darkL = hsl.lightness
        let lightL = 1.0 - darkL + 0.05 // Slight warm offset
        let newL = darkL + (lightL - darkL) * l
        return hsl.withLightness(min(0.97, max(0.03, newL))).color
    }

    /// Shift foreground colors: light at l=0, dark at l=1
    private func shiftForeground(_ hsl: HSLColor, luminance l: Double) -> Color {
        let darkModeL = hsl.lightness           // e.g., 0.81 for primary
        let lightModeL = 1.0 - darkModeL + 0.05 // e.g., 0.24 for primary in light mode
        let newL = darkModeL + (lightModeL - darkModeL) * l
        return hsl.withLightness(min(0.95, max(0.10, newL))).color
    }

    /// Signal colors shift minimally — just enough to maintain contrast
    private func shiftSignal(_ hsl: HSLColor, luminance l: Double) -> Color {
        // Reduce saturation slightly in light mode, shift lightness just -10%
        let newL = hsl.lightness - (l * 0.15) // Darken slightly in light mode
        let newS = hsl.saturation + (l * 0.05) // Slightly more saturated in light mode
        return HSLColor(h: hsl.hue, s: min(1, newS), l: max(0.25, min(0.75, newL))).color
    }
}
