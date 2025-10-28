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
    private var lastProcessedLength: Int = 0
    var fullTranscript: String = ""  // Add this to keep the full transcript
    
    private var audioEngine = AVAudioEngine()
    private var transcribeClient: TranscribeStreamingClient?
    private var transcriptionTask: Task<Void, Error>?
    
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
        print("Starting transcription service...")
        guard !isTranscribing else {
            print("Already transcribing - ignoring request")
            return
        }
        
        let granted = await requestMicrophonePermission()
        guard granted else {
            self.transcript = "Microphone access required"
            return
        }
        
        isTranscribing = true
        transcript = ""
        
        do {
            let region = SettingManager.shared.selectedRegion.rawValue
            let config = try await TranscribeStreamingClient.TranscribeStreamingClientConfiguration(region: region)
            transcribeClient = TranscribeStreamingClient(config: config)
            
            let audioStream = createAudioStream()
            
            // Configure transcription input with correct initialization
            let input = StartStreamTranscriptionInput(
                audioStream: audioStream,
                languageCode: TranscribeStreamingClientTypes.LanguageCode(rawValue: "en-US")!,
                mediaEncoding: .pcm,
                mediaSampleRateHertz: sampleRate
            )
            
            guard let output = try await transcribeClient?.startStreamTranscription(input: input) else {
                self.transcript = "Failed to start transcription stream"
                return
            }
            
            transcriptionTask = Task<Void, Error> {
                guard let transcriptStream = output.transcriptResultStream else {
                    throw NSError(domain: "Transcription",
                                  code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Invalid stream"])
                }
                
                for try await event in transcriptStream {
                    if case .transcriptevent(let transcribeEvent) = event {
                        for result in transcribeEvent.transcript?.results ?? [] {
                            if let alternative = result.alternatives?.first,
                               let newText = alternative.transcript {
                                
                                await MainActor.run {
                                    if !result.isPartial {
                                        // This is a final result, append it to full transcript
                                        if !fullTranscript.isEmpty && !fullTranscript.hasSuffix(" ") {
                                            fullTranscript += " "
                                        }
                                        fullTranscript += newText
                                        self.transcript = fullTranscript
                                        lastProcessedLength = 0
                                    } else {
                                        // This is a partial result, show it alongside the full transcript
                                        var currentText = fullTranscript
                                        if !currentText.isEmpty && !currentText.hasSuffix(" ") {
                                            currentText += " "
                                        }
                                        currentText += newText
                                        self.transcript = currentText
                                    }
                                    
                                    NotificationCenter.default.post(
                                        name: .transcriptUpdated,
                                        object: nil,
                                        userInfo: ["newText": newText]
                                    )
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            self.transcript = "Transcription error: \(error.localizedDescription)"
            stopTranscription()
        }
    }
    
    /// Stops capturing audio and cancels the transcription.
    func stopTranscription() {
        guard isTranscribing else { return }
        isTranscribing = false
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        transcriptionTask?.cancel()
        fullTranscript = ""  // Reset full transcript when stopping
        lastProcessedLength = 0
        transcribeClient = nil
    }
    
    /// Creates an AsyncThrowingStream that sends microphone audio as PCM chunks.
    private func createAudioStream() -> AsyncThrowingStream<TranscribeStreamingClientTypes.AudioStream, Error> {
        // Capture audioEngine locally.
        nonisolated(unsafe) let engine = self.audioEngine
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
        
        return AsyncThrowingStream { continuation in
            let inputNode = engine.inputNode
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
                autoreleasepool {
                    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1024) else { return }
                    var error: NSError?
                    let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
                    if status == .haveData, let data = self.convertBufferToData(buffer: outputBuffer) {
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
            
            continuation.onTermination = { _ in
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
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
    private func convertBufferToData(buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else { return nil }
        let channelDataPointer = channelData.pointee
        let frameLength = Int(buffer.frameLength)
        return Data(bytes: channelDataPointer, count: frameLength * MemoryLayout<Int16>.size)
    }
}


extension Notification.Name {
    static let transcriptUpdated = Notification.Name("transcriptUpdated")
}

