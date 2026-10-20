// Created by Jinjia Ou on 10/19/26.

import SwiftUI
import UIKit

/// 只定义显示语义，不持有业务状态，也不改变用户的系统外观设置。
enum AppColors {
    static let canvas = adaptive(light: 0xE7E7E5, dark: 0x0C1012)
    static let background = adaptive(light: 0xF3F5F7, dark: 0x111517)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x191E20)
    static let elevatedSurface = adaptive(light: 0xFFFFFF, dark: 0x22282A)
    static let primaryText = adaptive(light: 0x18212D, dark: 0xE7EBE7)
    static let secondaryText = adaptive(light: 0x48576A, dark: 0xA1ACA8)
    static let tertiaryText = adaptive(light: 0x5E6B7C, dark: 0x7E8B87,
                                        highContrastLight: 0x354253, highContrastDark: 0xCDD5DF)
    static let border = adaptive(light: 0xD3DAE3, dark: 0x343C3E,
                                 highContrastLight: 0x677589, highContrastDark: 0x7E8B87)
    static let controlBorder = adaptive(light: 0x748195, dark: 0x7E8B87,
                                        highContrastLight: 0x354253, highContrastDark: 0xCDD5DF)
    static let accent = adaptive(light: 0x806000, dark: 0xECEE68)
    static let accentFill = adaptive(light: 0xECEE68, dark: 0xECEE68)
    static let onAccent = Color(uiColor: UIColor(rgb: 0x18212D))
    static let success = adaptive(light: 0x226847, dark: 0x56B9A0)
    static let warning = adaptive(light: 0x865000, dark: 0xD68D55)
    static let error = adaptive(light: 0xB22E3C, dark: 0xF27D7D)
    static let info = adaptive(light: 0x285F9D, dark: 0x80B7ED)
    static let disabledSurface = adaptive(light: 0xE4E8ED, dark: 0x2B3233)
    static let disabledText = adaptive(light: 0x5E6B7C, dark: 0x9EAAA5)

    private static func adaptive(light: UInt32, dark: UInt32,
                                 highContrastLight: UInt32? = nil,
                                 highContrastDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let enhanced = traits.accessibilityContrast == .high
            let value = isDark
                ? (enhanced ? highContrastDark ?? dark : dark)
                : (enhanced ? highContrastLight ?? light : light)
            return UIColor(rgb: value)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

enum AppTypography {
    static let pageTitle = Font.title2.weight(.bold)
    static let sectionTitle = Font.headline
    static let body = Font.body
    static let rowTitle = Font.subheadline.weight(.medium)
    static let supporting = Font.footnote
    static let caption = Font.caption
    static let button = Font.subheadline.weight(.semibold)
    static let metric = Font.title2.weight(.semibold).monospacedDigit()
    static let numeric = Font.subheadline.monospacedDigit()
    static let code = Font.system(.footnote, design: .monospaced)
}

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppRadius {
    static let control: CGFloat = 4
    static let surface: CGFloat = 6
    static let panel: CGFloat = 2
}

enum AppSize {
    static let touchTarget: CGFloat = 44
    static let rowMinimum: CGFloat = 52
    static let icon: CGFloat = 20
    static let itemIcon: CGFloat = 32
    static let metricColumnMinimum: CGFloat = 144
}

enum AppMotion {
    static func feedback(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    static func panel(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9)
    }
}

/// 供新页面逐步接入，不强制深色，也不新增 NavigationStack。
private struct AppPageStyle: ViewModifier {
    var topographicBackground = false
    func body(content: Content) -> some View {
        content
            .foregroundStyle(AppColors.primaryText)
            .tint(AppColors.accent)
            .background {
                if topographicBackground { AppTopographicBackground() }
                else { AppColors.background.ignoresSafeArea() }
            }
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func appPageStyle(topographicBackground: Bool = false) -> some View {
        modifier(AppPageStyle(topographicBackground: topographicBackground))
    }
}
