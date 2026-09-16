import AppKit
import SwiftUI

enum DesignTokens {
    static let accent = Color(light: .black, dark: .white)
    static let selection = Color(light: Color(rgba: 0x397e_e8ff), dark: Color(rgba: 0x589b_f5ff))
    static let canvas = Color.background
    static let sidebar = Color(light: Color(rgba: 0xf6f6_f6ff), dark: Color(rgba: 0x1717_17ff))
    static let surface = Color.secondaryBackground
    static let field = Color(light: .white, dark: Color(rgba: 0x2424_24ff))
    static let border = Color.primary.opacity(0.09)
    static let composerBorder = Color(light: .black.opacity(0.08), dark: .white.opacity(0.10))
    static let contentWidth: CGFloat = 800
    static let label = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let detail = Font.system(size: 11)
    static let pagePadding: CGFloat = 24
    static let rowHeight: CGFloat = 32
    static let controlSize: CGFloat = 32
}
