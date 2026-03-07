import SwiftUI

// MARK: - HSL Color Definition

struct HSLColor {
    let hue: Double        // 0-360
    let saturation: Double // 0-1
    let lightness: Double  // 0-1
    let alpha: Double

    init(h: Double, s: Double, l: Double, a: Double = 1.0) {
        self.hue = h
        self.saturation = s
        self.lightness = l
        self.alpha = a
    }

    /// Shift lightness by a delta, clamped to 0-1
    func withLightness(_ newL: Double) -> HSLColor {
        HSLColor(h: hue, s: saturation, l: max(0, min(1, newL)), a: alpha)
    }

    /// Convert HSL to SwiftUI Color (via RGB to avoid HSL/HSB model mismatch)
    var color: Color {
        let (r, g, b) = hslToRGB()
        return Color(red: r, green: g, blue: b, opacity: alpha)
    }

    /// Convert HSL to NSColor for AppKit interop
    var nsColor: NSColor {
        let (r, g, b) = hslToRGB()
        return NSColor(red: r, green: g, blue: b, alpha: alpha)
    }

    // HSL to RGB conversion
    private func hslToRGB() -> (Double, Double, Double) {
        let h = hue / 360.0
        let s = saturation
        let l = lightness

        if s == 0 {
            return (l, l, l)
        }

        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q

        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0/6.0 { return p + (q - p) * 6 * t }
            if t < 1.0/2.0 { return q }
            if t < 2.0/3.0 { return p + (q - p) * (2.0/3.0 - t) * 6 }
            return p
        }

        return (
            hueToRGB(p, q, h + 1.0/3.0),
            hueToRGB(p, q, h),
            hueToRGB(p, q, h - 1.0/3.0)
        )
    }
}

// MARK: - Color Palette

/// All colors from UX_DESIGN.md, defined in HSL for luminance shifting
struct ColorPalette {

    // MARK: Background Tiers (darkest to lightest at default luminance)
    // These shift dramatically with luminance

    static let base      = HSLColor(h: 230, s: 0.08, l: 0.11)   // #1A1B1E
    static let surface   = HSLColor(h: 230, s: 0.06, l: 0.14)   // #222327
    static let elevated  = HSLColor(h: 230, s: 0.06, l: 0.17)   // #2A2B30
    static let overlay   = HSLColor(h: 230, s: 0.06, l: 0.21)   // #32333A

    // MARK: Foreground Tiers (dimmest to brightest)

    static let muted     = HSLColor(h: 225, s: 0.06, l: 0.39)   // #5C5F6A
    static let secondary = HSLColor(h: 225, s: 0.10, l: 0.58)   // #8B8FA0
    static let primary   = HSLColor(h: 225, s: 0.12, l: 0.81)   // #C8CCD8
    static let bright    = HSLColor(h: 225, s: 0.16, l: 0.93)   // #E8ECF4

    // MARK: Signal Colors (shift minimally with luminance)

    static let sky       = HSLColor(h: 207, s: 0.58, l: 0.69)   // #7EB8E0
    static let sage      = HSLColor(h: 145, s: 0.30, l: 0.65)   // #8BBF9F
    static let sand      = HSLColor(h: 30,  s: 0.45, l: 0.71)   // #D4B896
    static let rose      = HSLColor(h: 0,   s: 0.35, l: 0.62)   // #C47A7A
    static let lavender  = HSLColor(h: 265, s: 0.30, l: 0.68)   // #A594C8
    static let amber     = HSLColor(h: 37,  s: 0.55, l: 0.60)   // #D4A85C
}
