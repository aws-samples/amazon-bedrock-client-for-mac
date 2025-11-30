//
//  QuickAccessWindowManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 9/17/25.
//

import Cocoa
import SwiftUI
import Logging

class QuickAccessWindow: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

@MainActor
class QuickAccessWindowManager: NSObject, ObservableObject {
    static let shared = QuickAccessWindowManager()
    
    private var window: QuickAccessWindow?
    private let logger = Logger(label: "QuickAccessWindowManager")
    private var isFileUploadInProgress = false
    
    private override init() {
        super.init()
    }
    
    func showWindow() {
        // 기존 윈도우가 있으면 앞으로 가져오기
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // 새 윈도우 생성
        let contentView = QuickAccessView(
            onClose: { [weak self] in
                self?.hideWindow()
            },
            onHeightChange: { [weak self] newHeight in
                self?.updateWindowHeight(newHeight)
            }
        )
        
        let hostingView = NSHostingView(rootView: contentView)
        
        // Fix theme flickering - inherit from system appearance
        hostingView.wantsLayer = true
        
        // 윈도우 위치 계산 (화면 중앙)
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowWidth: CGFloat = 500
        let windowHeight: CGFloat = 56
        let windowRect = NSRect(
            x: screenFrame.midX - windowWidth / 2,
            y: screenFrame.midY + 100, // 화면 중앙보다 약간 위
            width: windowWidth,
            height: windowHeight
        )
        
        // NSPanel 생성 (floating window에 적합)
        window = QuickAccessWindow(
            contentRect: windowRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        guard let window = window else { return }
        
        // 윈도우 설정
        window.contentView = hostingView
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isFloatingPanel = true
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        // Fix theme flickering - use system appearance
        window.appearance = NSApp.effectiveAppearance
        
        // 트래픽 라이트 버튼 숨기기
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        // 윈도우 표시
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        logger.info("Quick access window shown")
    }
    
    func hideWindow() {
        if let window = window {
            window.orderOut(nil)
            self.window = nil
            logger.info("Quick access window hidden")
        }
    }
    
    func toggleWindow() {
        if window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
    }
    
    private func updateWindowHeight(_ newHeight: CGFloat) {
        guard let window = window else { return }
        
        let currentFrame = window.frame
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        
        // 새로운 높이로 윈도우 크기 조정
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: screenFrame.midY + 100 - newHeight / 2, // 중앙 정렬 유지
            width: currentFrame.width,
            height: newHeight
        )
        
        // 애니메이션과 함께 크기 조정
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }
    
    func setFileUploadInProgress(_ inProgress: Bool) {
        isFileUploadInProgress = inProgress
        logger.info("File upload in progress: \(inProgress)")
        
        // 파일 업로드 중일 때 윈도우 레벨을 조정
        guard let window = window else { return }
        
        if inProgress {
            // 파일 선택 윈도우보다 아래로 내리기
            window.level = .normal
        } else {
            // 다시 floating 레벨로 올리기
            window.level = .floating
        }
    }
}

// MARK: - NSWindowDelegate
extension QuickAccessWindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
        logger.info("Quick access window closed")
    }
    
    func windowDidResignKey(_ notification: Notification) {
        // 파일 업로드 중이면 윈도우를 닫지 않음
        guard !isFileUploadInProgress else {
            logger.info("File upload in progress, not closing window")
            return
        }
        
        // 포커스를 잃으면 윈도우 닫기 (약간의 지연을 두어 안정성 확보)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            // 다시 한 번 체크 (지연 시간 동안 파일 업로드가 시작될 수 있음)
            guard let self = self, !self.isFileUploadInProgress else { return }
            self.hideWindow()
        }
    }
}