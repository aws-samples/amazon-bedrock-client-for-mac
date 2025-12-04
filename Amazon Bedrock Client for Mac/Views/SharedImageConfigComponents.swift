//
//  SharedImageConfigComponents.swift
//  Amazon Bedrock Client for Mac
//
//  Shared UI components for image generation config dropdowns
//

import SwiftUI

// MARK: - Image Config Section Header
struct ImageConfigSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}



// MARK: - Image Config Dropdown Modifier
struct ImageConfigDropdownModifier: ViewModifier {
    let isHovering: Bool
    let colorScheme: ColorScheme
    let accentColor: Color
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ?
                              Color(NSColor.controlBackgroundColor).opacity(0.8) :
                              Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isHovering ? accentColor.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 3 : 2, x: 0, y: 1)
                )
        }
    }
}

// MARK: - Image Task Type Row
struct ImageTaskTypeRow: View {
    let icon: String
    let name: String
    let description: String
    let isSelected: Bool
    let requiresImage: Bool
    let accentColor: Color
    var isDisabled: Bool = false
    let onSelect: () -> Void
    
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isDisabled ? .gray.opacity(0.5) : (isSelected ? accentColor : .secondary))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDisabled ? Color.gray.opacity(0.05) : (isSelected ? accentColor.opacity(0.15) : Color.gray.opacity(0.1)))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDisabled ? .gray.opacity(0.6) : .primary)
                    
                    if isSelected && !isDisabled {
                        Image(systemName: "checkmark")
                            .foregroundColor(accentColor)
                            .font(.system(size: 10, weight: .bold))
                    }
                    
                    if isDisabled {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.gray.opacity(0.5))
                            .font(.system(size: 9))
                    }
                }
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(isDisabled ? .gray.opacity(0.5) : .secondary)
            }
            
            Spacer()
            
            if requiresImage && !isDisabled {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 11))
                    .foregroundColor(accentColor.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDisabled ? Color.clear :
                      (isSelected ?
                       accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08) :
                        (isHovering ? Color.gray.opacity(0.08) : Color.clear)))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if !isDisabled {
                withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
        }
        .onTapGesture {
            if !isDisabled {
                onSelect()
            }
        }
        .opacity(isDisabled ? 0.7 : 1.0)
    }
}

// MARK: - Compact Size Field
struct CompactSizeField: View {
    let label: String
    @Binding var value: Int
    let onChange: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .onChange(of: value) { _, _ in onChange() }
        }
    }
}

// MARK: - Quick Size Button
struct QuickSizeButton: View {
    let label: String
    let w: Int
    let h: Int
    let currentW: Int
    let currentH: Int
    let color: Color
    let action: () -> Void
    
    private var isSelected: Bool { currentW == w && currentH == h }
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .foregroundColor(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Aspect Ratio Button
struct AspectRatioButton: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? color.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .foregroundColor(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}
