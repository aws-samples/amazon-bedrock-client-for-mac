import SwiftUI

/// Explicit glyph bounds prevent NSToolbar from enlarging SF Symbols when it
/// converts a SwiftUI label to a template image. Hit targets remain 32 points.
struct ToolbarIcon: View {
    let symbol: String
    var weight: Font.Weight = .regular
    init(_ symbol: String, weight: Font.Weight = .regular) {
        self.symbol = symbol
        self.weight = weight
    }
    var body: some View {
        Image(systemName: symbol)
            .resizable().scaledToFit()
            .fontWeight(weight)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }
}

enum AppMotion {
    static let standard = Animation.spring(response: 0.28, dampingFraction: 0.9)
    static let feedback = Animation.easeOut(duration: 0.12)
}

struct AppButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlSize) private var size
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignTokens.label)
            .foregroundStyle(configuration.role == .destructive ? Color.red :
                                prominent ? DesignTokens.canvas : Color.primary)
            .padding(.horizontal, size == .small || size == .mini ? 9 : 12)
            .frame(minHeight: size == .small || size == .mini ? 26 : 32)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(prominent ? DesignTokens.accent : Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.065 : 0.035))
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesignTokens.border))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.38)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : AppMotion.feedback, value: configuration.isPressed)
            .animation(reduceMotion ? nil : AppMotion.feedback, value: hovered)
    }
}

struct AppSwitchStyle: ToggleStyle {
    var showsLabel = true
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                if showsLabel {
                    configuration.label.font(DesignTokens.body)
                    Spacer(minLength: 8)
                }
                Capsule()
                    .fill(configuration.isOn ? DesignTokens.selection : Color.primary.opacity(0.16))
                    .overlay {
                        Circle().fill(.white).frame(width: 16, height: 16)
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            .offset(x: configuration.isOn ? 7 : -7)
                    }
                    .frame(width: 36, height: 22)
            }
            .foregroundStyle(.primary).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .animation(reduceMotion ? nil : AppMotion.standard, value: configuration.isOn)
    }
}

struct AppSegmentedControl<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var options: [(value: Value, title: String)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button { selection = option.value } label: {
                    Text(option.title).font(DesignTokens.caption)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .foregroundStyle(selection == option.value ? .primary : .secondary)
                        .background(selection == option.value ? DesignTokens.field : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selection == option.value ? DesignTokens.border : .clear))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(3).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain).accessibilityLabel(title)
        .animation(reduceMotion ? nil : AppMotion.feedback, value: selection)
    }
}

/// Shared custom field and searchable menu. No system bevel, double arrows, or
/// fixed label columns; long profile/region names share the same layout.
struct SelectionField<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 8) {
                Text(options.first(where: { $0.value == selection })?.title ?? "Select…")
                    .font(DesignTokens.body).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11).frame(height: 34)
            .background(DesignTokens.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(presented ? DesignTokens.selection.opacity(0.65) : DesignTokens.border))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).foregroundStyle(.primary)
        .accessibilityLabel(title)
        .accessibilityValue(options.first(where: { $0.value == selection })?.title ?? "")
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            SelectionOptions(title: title, selection: $selection, options: options) { presented = false }
        }
    }
}

private struct SelectionOptions<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    var close: () -> Void
    @State private var query = ""
    @State private var focusedIndex: Int?
    @FocusState private var menuFocused: Bool
    @FocusState private var searchFocused: Bool
    private var visible: [Int] { options.indices.filter { query.isEmpty || options[$0].title.localizedStandardContains(query) } }
    var body: some View {
        VStack(spacing: 6) {
            if options.count > 8 {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search \(title.lowercased())", text: $query)
                        .textFieldStyle(.plain).focused($searchFocused)
                        .onSubmit { if let index = focusedIndex ?? visible.first { choose(index) } }
                }
                .font(DesignTokens.body).padding(9)
                .background(DesignTokens.field, in: RoundedRectangle(cornerRadius: 7)).padding(6)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visible, id: \.self) { index in
                            Button { choose(index) } label: {
                                HStack(spacing: 9) {
                                    Text(options[index].title).font(DesignTokens.body).lineLimit(2)
                                    Spacer(minLength: 8)
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                        .opacity(options[index].value == selection ? 1 : 0)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(focusedIndex == index ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain).foregroundStyle(.primary)
                            .onHover { if $0 { focusedIndex = index } }
                            .accessibilityAddTraits(options[index].value == selection ? .isSelected : [])
                            .id(index)
                        }
                        if visible.isEmpty { Text("No matches").font(DesignTokens.caption).foregroundStyle(.secondary).padding(16) }
                    }.padding(6)
                }
                .frame(maxHeight: 300).fixedSize(horizontal: false, vertical: true)
                .background(SidebarScrollChrome())
                .onChange(of: focusedIndex) { _, index in if let index { proxy.scrollTo(index) } }
            }
        }
        .frame(width: 300)
        .padding(4)
        .background(PopoverFocus().frame(width: 0, height: 0))
        .focusable().focused($menuFocused).focusEffectDisabled()
        .onAppear {
            focusedIndex = options.firstIndex(where: { $0.value == selection })
            if options.count > 8 { searchFocused = true } else { menuFocused = true }
        }
        .onChange(of: query) { _, _ in focusedIndex = visible.first }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) { if let index = focusedIndex ?? visible.first { choose(index) }; return .handled }
        .onExitCommand(perform: close)
        .accessibilityLabel(title)
    }
    private func choose(_ index: Int) { selection = options[index].value; close() }
    private func move(_ delta: Int) {
        let rows = visible
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0 == focusedIndex } ?? (delta > 0 ? -1 : rows.count)
        focusedIndex = rows[min(max(0, index + delta), rows.count - 1)]
    }
}

struct ActionMenu<Label: View, Content: View>: View {
    var horizontalPadding: CGFloat = 4
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label
    @State private var presented = false
    @State private var hovered = false

    var body: some View {
        Button { presented.toggle() } label: {
            label().font(DesignTokens.body)
                .padding(.horizontal, horizontalPadding).frame(minHeight: 30)
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .background(Color.primary.opacity(hovered || presented ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).foregroundStyle(.primary).onHover { hovered = $0 }
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) { content() }
                    .buttonStyle(MenuActionStyle(close: { presented = false }))
                    .padding(6)
            }
            .frame(width: 240).frame(maxHeight: 440).fixedSize(horizontal: false, vertical: true)
            .background(PopoverFocus().frame(width: 0, height: 0))
            .onExitCommand { presented = false }
        }
    }
}

extension ActionMenu where Label == Text {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.label = { Text(title) }
    }
}

private struct MenuActionStyle: PrimitiveButtonStyle {
    var close: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        Button {
            close()
            DispatchQueue.main.async { configuration.trigger() }
        } label: {
            configuration.label
                .font(DesignTokens.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(configuration.role == .destructive ? Color.red : .primary)
        }.buttonStyle(MenuRowStyle())
    }
}

private struct MenuRowStyle: ButtonStyle {
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : hovered ? 0.065 : 0), in: RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovered = $0 }
    }
}

// MARK: - Liquid Glass Toolbar Button Style (macOS 26+ Tahoe compatible)
struct LiquidGlassToolbarButtonStyle: ButtonStyle {
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
            .frame(width: 32, height: 32)
            .background {
                Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0))
            }
            .contentShape(Circle())
            .opacity(enabled ? 1 : 0.32)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Scroll Edge Effect Modifier (Shared)
struct ScrollEdgeEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
