//
//  NovaReelConfigDropdown.swift
//  Amazon Bedrock Client for Mac
//
//  Dropdown for Amazon Nova Reel video generation settings
//

import SwiftUI

// MARK: - Nova Reel Config Dropdown
struct NovaReelConfigDropdown: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @State private var isShowingPopover = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var selectedTaskType: NovaReelTaskType {
        NovaReelTaskType(rawValue: settingManager.novaReelConfig.taskType) ?? .textToVideo
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isShowingPopover.toggle()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: selectedTaskType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                
                Text(selectedTaskType.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(isShowingPopover ? Angle(degrees: 180) : Angle(degrees: 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShowingPopover)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .modifier(NovaReelDropdownModifier(isHovering: isHovering, colorScheme: colorScheme))
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) { isHovering = hovering }
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            NovaReelConfigPopoverContent(isShowingPopover: $isShowingPopover)
                .frame(width: 360, height: 480)
        }
    }
}

// MARK: - Popover Content
struct NovaReelConfigPopoverContent: View {
    @ObservedObject private var settingManager = SettingManager.shared
    @Binding var isShowingPopover: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedTaskType: NovaReelTaskType = .textToVideo
    @State private var durationSeconds: Int = 6
    @State private var seed: Int = 0
    @State private var s3OutputBucket: String = ""
    @State private var shots: [String] = [""]
    @State private var showS3Warning: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "film")
                    .foregroundColor(.red)
                Text("Nova Reel Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Reset") { resetToDefaults() }
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.textBackgroundColor).opacity(0.7))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Info banner
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Videos are saved to S3. Generation takes ~90s per 6s.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    
                    // Task Types
                    NovaReelSectionHeader(title: "Generation Mode")
                    
                    ForEach(NovaReelTaskType.allCases) { taskType in
                        NovaReelTaskTypeRow(
                            taskType: taskType,
                            isSelected: selectedTaskType == taskType,
                            onSelect: {
                                selectedTaskType = taskType
                                // Reset duration for single shot
                                if taskType == .textToVideo {
                                    durationSeconds = 6
                                } else if durationSeconds < 12 {
                                    durationSeconds = 12
                                }
                                saveConfig()
                            }
                        )
                    }
                    
                    Divider().padding(.vertical, 8)
                    
                    // S3 Output Bucket (Required)
                    NovaReelSectionHeader(title: "S3 Output Location")
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("s3://your-bucket/videos", text: $s3OutputBucket)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onChange(of: s3OutputBucket) { _, newValue in
                                showS3Warning = !newValue.isEmpty && !newValue.hasPrefix("s3://")
                                saveConfig()
                            }
                        
                        if showS3Warning {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 10))
                                Text("Must start with 's3://'")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("S3 bucket must be in us-east-1 region")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Text("Example: s3://my-bucket or s3://my-bucket/videos")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    
                    Divider().padding(.vertical, 8)
                    
                    // Duration (for multi-shot modes)
                    if selectedTaskType != .textToVideo {
                        NovaReelSectionHeader(title: "Video Duration")
                        
                        Picker("", selection: $durationSeconds) {
                            ForEach(NovaReelService.durationOptions.filter { $0.seconds >= 12 }, id: \.seconds) { option in
                                Text(option.label).tag(option.seconds)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                        .onChange(of: durationSeconds) { _, _ in saveConfig() }
                        
                        Text("Estimated time: \(NovaReelService.estimatedTime(durationSeconds: durationSeconds))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        
                        Divider().padding(.vertical, 8)
                    }
                    
                    // Manual shots (for manual mode)
                    if selectedTaskType == .multiShotManual {
                        NovaReelSectionHeader(title: "Shot Descriptions")
                        
                        VStack(spacing: 8) {
                            ForEach(shots.indices, id: \.self) { index in
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    
                                    TextField("Shot \(index + 1) description...", text: $shots[index])
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11))
                                        .onChange(of: shots[index]) { _, _ in saveConfig() }
                                    
                                    if shots.count > 2 {
                                        Button(action: { removeShot(at: index) }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red.opacity(0.7))
                                                .font(.system(size: 14))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            
                            if shots.count < 20 {
                                Button(action: addShot) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Shot")
                                    }
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        
                        Divider().padding(.vertical, 8)
                    }
                    
                    // Settings
                    NovaReelSectionHeader(title: "Settings")
                    
                    VStack(spacing: 12) {
                        // Output info
                        HStack {
                            Text("Resolution").font(.system(size: 12))
                            Spacer()
                            Text("1280 × 720")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Frame Rate").font(.system(size: 12))
                            Spacer()
                            Text("24 fps")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        // Seed
                        HStack {
                            Text("Seed").font(.system(size: 12))
                            Spacer()
                            TextField("", value: $seed, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onChange(of: seed) { _, _ in saveConfig() }
                            Button(action: { seed = 0; saveConfig() }) {
                                Image(systemName: "dice")
                                    .font(.system(size: 12))
                                    .foregroundColor(seed == 0 ? .red : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("0 = Random seed (default: 42)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear { loadConfig() }
    }
    
    // MARK: - Helpers
    
    private func addShot() {
        shots.append("")
        durationSeconds = shots.count * 6
        saveConfig()
    }
    
    private func removeShot(at index: Int) {
        guard shots.count > 2 else { return }
        shots.remove(at: index)
        durationSeconds = shots.count * 6
        saveConfig()
    }
    
    private func loadConfig() {
        let config = settingManager.novaReelConfig
        selectedTaskType = NovaReelTaskType(rawValue: config.taskType) ?? .textToVideo
        durationSeconds = config.durationSeconds
        seed = config.seed
        s3OutputBucket = config.s3OutputBucket
        shots = config.shots.isEmpty ? ["", ""] : config.shots
    }
    
    private func saveConfig() {
        settingManager.novaReelConfig = NovaReelConfig(
            taskType: selectedTaskType.rawValue,
            durationSeconds: durationSeconds,
            seed: seed,
            s3OutputBucket: s3OutputBucket,
            shots: shots.filter { !$0.isEmpty }
        )
    }
    
    private func resetToDefaults() {
        let defaults = NovaReelConfig.defaultConfig
        selectedTaskType = NovaReelTaskType(rawValue: defaults.taskType) ?? .textToVideo
        durationSeconds = defaults.durationSeconds
        seed = defaults.seed
        // Keep s3OutputBucket as user likely wants to keep it
        shots = ["", ""]
        saveConfig()
    }
}

// MARK: - Task Type Row
struct NovaReelTaskTypeRow: View {
    let taskType: NovaReelTaskType
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: taskType.icon)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? .red : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.red.opacity(0.15) : Color.gray.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(taskType.displayName)
                        .font(.system(size: 13, weight: .medium))
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.red)
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                
                Text(taskType.taskDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if taskType.supportsInputImage {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ?
                      Color.red.opacity(colorScheme == .dark ? 0.15 : 0.08) :
                        (isHovering ? Color.gray.opacity(0.08) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Section Header
struct NovaReelSectionHeader: View {
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

// MARK: - Dropdown Modifier
struct NovaReelDropdownModifier: ViewModifier {
    let isHovering: Bool
    let colorScheme: ColorScheme
    
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
                                .stroke(isHovering ? Color.red.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 3 : 2, x: 0, y: 1)
                )
        }
    }
}
