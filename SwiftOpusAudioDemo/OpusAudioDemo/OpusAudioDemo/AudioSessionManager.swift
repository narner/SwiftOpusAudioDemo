//
//  AudioSessionManager.swift
//  OpusAudioDemo
//
//  Created by Nicholas Arner on 8/15/24.
//

import AVFoundation
import Opus

class AudioManager: ObservableObject {
    private var audioEngine: AVAudioEngine!
    private var inputNode: AVAudioInputNode!
    private var playerNode: AVAudioPlayerNode!
    private var encoder: Opus.Encoder?
    private var decoder: Opus.Decoder?
    private var encodedPackets: [Data] = []
    
    private let OPUS_ENCODER_SAMPLE_RATE: Double = 48000
    private let OPUS_ENCODER_DURATION_MS: Int = 20
    private let AUDIO_OUTPUT_SAMPLE_RATE: Double = 48000
    private let AUDIO_OUTPUT_CHANNELS: AVAudioChannelCount = 1
    
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var statusMessage = "Initializing..."
    @Published var hasMicrophonePermission = false
    @Published var isAudioEngineReady = false
    
    func setup() {
        setupAudio()
        requestMicrophonePermission()
    }
    
    private func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            audioEngine = AVAudioEngine()
            inputNode = audioEngine.inputNode
            playerNode = AVAudioPlayerNode()
            audioEngine.attach(playerNode)
            
            let inputFormat = AVAudioFormat(standardFormatWithSampleRate: OPUS_ENCODER_SAMPLE_RATE, channels: 1)!
            let outputFormat = AVAudioFormat(standardFormatWithSampleRate: AUDIO_OUTPUT_SAMPLE_RATE, channels: AUDIO_OUTPUT_CHANNELS)!
            
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: outputFormat)
            
            encoder = try Opus.Encoder(format: inputFormat, application: .voip)
            decoder = try Opus.Decoder(format: outputFormat, application: .voip)
            
            audioEngine.prepare()
            
            try audioEngine.start()
            isAudioEngineReady = true
            statusMessage = "Audio engine started"
        } catch {
            statusMessage = "Failed to setup audio: \(error.localizedDescription)"
            print("Audio setup error: \(error)")
        }
    }
    
    private func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.hasMicrophonePermission = granted
                self.statusMessage = granted ? "Ready to record" : "Microphone access denied"
            }
        }
    }
    
    func startRecording() {
        guard hasMicrophonePermission && isAudioEngineReady else {
            statusMessage = "Cannot start recording: Missing permissions or audio engine not ready"
            return
        }
        
        do {
            let inputFormat = AVAudioFormat(standardFormatWithSampleRate: OPUS_ENCODER_SAMPLE_RATE, channels: 1)!
            let desiredBufferSize = AVAudioFrameCount((Double(OPUS_ENCODER_DURATION_MS) / 1000.0) * OPUS_ENCODER_SAMPLE_RATE)
            
            inputNode.installTap(onBus: 0, bufferSize: desiredBufferSize, format: inputFormat) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }
            
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            
            isRecording = true
            statusMessage = "Recording..."
        } catch {
            statusMessage = "Failed to start recording: \(error.localizedDescription)"
            print("Recording start error: \(error)")
        }
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let encoder = encoder else { return }
        
        do {
            var encodedData = Data(count: Int(buffer.frameLength) * MemoryLayout<Float32>.size)
            _ = try encoder.encode(buffer, to: &encodedData)
            encodedPackets.append(encodedData)
        } catch {
            print("Failed to encode buffer: \(error.localizedDescription)")
        }
    }
    
    func stopRecordingAndPlay() {
        inputNode.removeTap(onBus: 0)
        isRecording = false
        statusMessage = "Processing and playing back..."
        
        let decodedBuffers = decodePackets()
        scheduleBuffersForPlayback(decodedBuffers)
        
        playerNode.play()
        isPlaying = true
    }
    
    private func decodePackets() -> [AVAudioPCMBuffer] {
        var decodedBuffers: [AVAudioPCMBuffer] = []
        
        for packet in encodedPackets {
            guard let decoder = decoder else { continue }
            do {
                let decodedBuffer = try decoder.decode(packet)
                decodedBuffers.append(decodedBuffer)
            } catch {
                print("Failed to decode packet: \(error.localizedDescription)")
            }
        }
        
        return decodedBuffers
    }
    
    private func scheduleBuffersForPlayback(_ buffers: [AVAudioPCMBuffer]) {
        guard !buffers.isEmpty else {
            DispatchQueue.main.async {
                self.statusMessage = "No audio to play"
                self.isPlaying = false
            }
            return
        }
        
        for (index, buffer) in buffers.enumerated() {
            if index == buffers.count - 1 {
                // For the last buffer, use scheduleBuffer(completionHandler:)
                playerNode.scheduleBuffer(buffer) {
                    DispatchQueue.main.async {
                        self.statusMessage = "Playback complete"
                        self.isPlaying = false
                        self.encodedPackets.removeAll()
                    }
                }
            } else {
                playerNode.scheduleBuffer(buffer)
            }
        }
    }
}
