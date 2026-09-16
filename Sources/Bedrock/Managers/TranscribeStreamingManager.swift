//
//  TranscribeStreamingManager.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2/17/25.
//

@preconcurrency import AVFoundation
import AWSTranscribeStreaming
import AWSClientRuntime
import Combine
import Foundation
import SwiftUI
@preconcurrency import AVKit

@MainActor
class TranscribeStreamingManager: ObservableObject {
    @Published var transcript: String = ""
    @Published var isTranscribing: Bool = false
    @Published var errorMessage: String?
    private var sessionID = UUID()
    private var tapInstalled = false
    private var lastProcessedLength: Int = 0
    var fullTranscript: String = ""  // Add this to keep the full transcript
    
    private var audioEngine = AVAudioEngine()
    private var transcribeClient: TranscribeStreamingClient?
    private var transcriptionTask: Task<Void, Never>?
    
    // Use 16kHz, mono, 16-bit PCM audio.
    private let sampleRate = 16000
    
    /// Requests microphone access.
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    func resetTranscript() {
        transcript = ""
        fullTranscript = ""
        lastProcessedLength = 0
    }
    
    /// Starts capturing microphone audio and streams it to Amazon Transcribe.
    func startTranscription() async {
        guard !isTranscribing else { return }
        let id = UUID()
        sessionID = id
        isTranscribing = true
        errorMessage = nil
        resetTranscript()
        let granted = await requestMicrophonePermission()
        guard id == sessionID else { return }
        guard granted else {
            errorMessage = "Allow microphone access in System Settings to use dictation."
            isTranscribing = false
            return
        }
        do {
            let settings = SettingManager.shared
            let backend = try Backend(region: settings.selectedRegion.rawValue, profile: settings.selectedProfile,
                                      endpoint: settings.endpoint, runtimeEndpoint: settings.runtimeEndpoint, profiles: settings.profiles)
            let config = try await TranscribeStreamingClient.TranscribeStreamingClientConfig(
                awsCredentialIdentityResolver: backend.awsCredentialIdentityResolver, region: settings.selectedRegion.rawValue)
            guard id == sessionID else { return }
            let client = TranscribeStreamingClient(config: config)
            transcribeClient = client
            let input = StartStreamTranscriptionInput(
                audioStream: createAudioStream(), languageCode: .enUs, mediaEncoding: .pcm, mediaSampleRateHertz: sampleRate)
            let output = try await client.startStreamTranscription(input: input)
            guard id == sessionID else { return }
            transcriptionTask = Task { [weak self] in
                guard let self else { return }
                defer { if sessionID == id { stopTranscription() } }
                do {
                    guard let stream = output.transcriptResultStream else { throw LocalWorkbenchError.invalid("Transcribe returned no audio transcript stream.") }
                    for try await event in stream {
                        try Task.checkCancellation()
                        guard sessionID == id else { return }
                        if case .transcriptevent(let value) = event {
                            for result in value.transcript?.results ?? [] {
                                guard let text = result.alternatives?.first?.transcript else { continue }
                                if !result.isPartial {
                                    fullTranscript += (fullTranscript.isEmpty ? "" : " ") + text
                                    transcript = fullTranscript
                                } else { transcript = fullTranscript + (fullTranscript.isEmpty ? "" : " ") + text }
                            }
                        }
                    }
                } catch {
                    if !Task.isCancelled && sessionID == id { errorMessage = "Dictation failed: \(error.localizedDescription)" }
                }
            }
        } catch {
            if id == sessionID {
                errorMessage = "Dictation failed: \(error.localizedDescription)"
                stopTranscription()
            }
        }
    }

    func stopTranscription() {
        sessionID = UUID()
        isTranscribing = false
        stopAudio()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        transcribeClient = nil
    }

    private func stopAudio() {
        if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        audioEngine.stop()
    }

    /// Creates an AsyncThrowingStream that sends microphone audio as PCM chunks.
    private func createAudioStream() -> AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error> {
        // Capture audioEngine locally.
        let engine = self.audioEngine
        let hwFormat = engine.inputNode.inputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: Double(sampleRate),
                                         channels: 1,
                                         interleaved: true)!
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(
                    domain: "AudioConversion",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to create audio converter"]
                ))
            }
        }
        
        let id = sessionID
        return AsyncThrowingStream { continuation in
            let inputNode = engine.inputNode
            tapInstalled = true
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
                autoreleasepool {
                    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1024) else { return }
                    var error: NSError?
                    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
                    if status == .haveData, let data = Self.convertBufferToData(buffer: outputBuffer) {
                        let audioEvent = TranscribeStreamingClientTypes.AudioStream.audioevent(.init(audioChunk: data))
                        continuation.yield(audioEvent)
                    }
                }
            }
            
            do {
                try engine.start()
            } catch {
                continuation.finish(throwing: error)
            }
            
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in if self?.sessionID == id { self?.stopAudio() } }
            }
        }
    }
    
    private func isSignificantAudio(buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.int16ChannelData else { return false }
        let channelDataPtr = channelData[0]
        let length = Int(buffer.frameLength)
        
        var sum: Int64 = 0
        for i in 0..<length {
            let sample = Int64(abs(Int32(channelDataPtr[i])))
            sum += sample
        }
        
        let average = Double(sum) / Double(length)
        let normalizedAverage = average / Double(Int16.max)
        
        // 노이즈 임계값 (조정 가능)
        return normalizedAverage > 0.01
    }
    
    /// Converts an AVAudioPCMBuffer to Data containing 16-bit little-endian PCM.
    nonisolated private static func convertBufferToData(buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else { return nil }
        let channelDataPointer = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        return Data(bytes: channelDataPointer, count: frameLength * MemoryLayout<Int16>.size)
    }
}


extension Notification.Name {
    static let transcriptUpdated = Notification.Name("transcriptUpdated")
}
