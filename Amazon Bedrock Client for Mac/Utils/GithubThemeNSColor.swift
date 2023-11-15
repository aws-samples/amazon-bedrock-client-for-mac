import AppKit

extension NSColor {
    convenience init(rgba: UInt32) {
        let red = CGFloat((rgba & 0xFF000000) >> 24) / 255.0
        let green = CGFloat((rgba & 0x00FF0000) >> 16) / 255.0
        let blue = CGFloat((rgba & 0x0000FF00) >> 8) / 255.0
        let alpha = CGFloat(rgba & 0x000000FF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    static let textLight = NSColor(rgba: 0x0606_06ff)
    static let textDark = NSColor(rgba: 0xfbfb_fcff)
    static let secondaryTextLight = NSColor(rgba: 0x6b6e_7bff)
    static let secondaryTextDark = NSColor(rgba: 0x9294_a0ff)
    static let backgroundLight = NSColor(rgba: 0xFFFFFFff)
    static let backgroundDark = NSColor(rgba: 0x1819_1dff)
    
    static var dynamicTextBackground: NSColor {
        if NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            // Dark mode background color
            return NSColor(rgba: 0x1819_1dff)
        } else {
            // Light mode background color
            return NSColor.textBackgroundColor
        }
    }
}
