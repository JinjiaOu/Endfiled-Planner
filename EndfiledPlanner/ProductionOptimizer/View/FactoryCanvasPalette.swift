// Created by Jinjia Ou on 10/19/26.

import SwiftUI

/// 工程纸与设备轮廓跟随系统外观；画布始终不使用动态等高线底纹。
enum FactoryCanvasPalette {
    static let background = AppColors.canvas
    static let building = AppColors.surface
    static let ink = AppColors.primaryText
    static let structure = AppColors.controlBorder
    static let secondaryInk = AppColors.secondaryText
    static let minorGrid = AppColors.primaryText.opacity(0.075)
    static let majorGrid = AppColors.primaryText.opacity(0.18)
    static let selection = AppColors.accent
    static let belt = AppColors.accentFill
    static let pipe = AppColors.primaryText
    static let beltArrow = AppColors.onAccent
    static let pipeArrow = AppColors.background
}
