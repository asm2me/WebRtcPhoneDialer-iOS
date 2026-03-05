import Foundation
import AVFoundation

protocol AudioServiceDelegate: AnyObject {
    func audioService(_ service: AudioService, didCapture encodedAudio: Data)
}

class AudioService {
    weak var delegate: AudioServiceDelegate?

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var isRunning = false
    private let codec: SIPConfiguration.AudioCodec

    // Audio format: 8kHz mono 16-bit PCM (for G.711 encoding)
    private let sampleRate: Double = 8000
    private let targetFormat: AVAudioFormat

    // Playback buffer
    private let playbackQueue = DispatchQueue(label: "com.webrtcphonedialer.audioplayback", qos: .userInteractive)

    init(codec: SIPConfiguration.AudioCodec = .pcmu) {
        self.codec = codec
        self.targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.020) // 20ms buffer
        try session.setActive(true)

        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        guard let engine = audioEngine, let player = playerNode else { return }

        engine.attach(player)

        // Connect player to output
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)

        // Install tap on input (microphone)
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Use a converter to downsample from device sample rate to 8kHz
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processMicrophoneInput(buffer: buffer, inputFormat: inputFormat)
        }

        try engine.start()
        player.play()
        isRunning = true

        Log.audio.info("Audio engine started (input: \(inputFormat.sampleRate)Hz, codec: \(self.codec.rawValue))")
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        isRunning = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Log.audio.info("Audio engine stopped")
    }

    // MARK: - Microphone processing

    private func processMicrophoneInput(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard isRunning else { return }

        // Convert to 8kHz mono Int16
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }

        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / inputFormat.sampleRate)
        guard frameCount > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

        var error: NSError?
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else { return }

        // Read Int16 samples
        guard let int16Data = convertedBuffer.int16ChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: int16Data[0], count: Int(convertedBuffer.frameLength)))

        // Encode to G.711 in 160-sample (20ms) frames
        var offset = 0
        while offset + PCMUCodec.samplesPerFrame <= samples.count {
            let frame = Array(samples[offset..<(offset + PCMUCodec.samplesPerFrame)])
            let encoded: Data
            switch codec {
            case .pcmu:
                encoded = PCMUCodec.encode(pcm: frame)
            case .pcma:
                encoded = PCMACodec.encode(pcm: frame)
            default:
                encoded = PCMUCodec.encode(pcm: frame) // Fallback to PCMU
            }
            delegate?.audioService(self, didCapture: encoded)
            offset += PCMUCodec.samplesPerFrame
        }
    }

    // MARK: - Playback

    func playAudio(encodedPayload: Data, payloadType: UInt8) {
        guard isRunning, let player = playerNode, let engine = audioEngine else { return }

        playbackQueue.async {
            // Decode from G.711 to PCM16
            let pcmSamples: [Int16]
            if payloadType == PCMUCodec.payloadType {
                pcmSamples = PCMUCodec.decode(mulaw: encodedPayload)
            } else if payloadType == PCMACodec.payloadType {
                pcmSamples = PCMACodec.decode(alaw: encodedPayload)
            } else {
                return
            }

            guard !pcmSamples.isEmpty else { return }

            // Create PCM buffer at 8kHz
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: AVAudioFrameCount(pcmSamples.count)) else { return }
            pcmBuffer.frameLength = AVAudioFrameCount(pcmSamples.count)

            if let channelData = pcmBuffer.int16ChannelData {
                for i in 0..<pcmSamples.count {
                    channelData[0][i] = pcmSamples[i]
                }
            }

            // Convert to output format for playback
            let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            guard let converter = AVAudioConverter(from: self.targetFormat, to: outputFormat) else { return }

            let outputFrameCount = AVAudioFrameCount(Double(pcmSamples.count) * outputFormat.sampleRate / self.sampleRate)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return pcmBuffer
            }

            guard error == nil else { return }

            player.scheduleBuffer(outputBuffer, completionHandler: nil)
        }
    }

    // MARK: - Audio route

    func enableSpeaker(_ enabled: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            if enabled {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
        } catch {
            Log.audio.error("Failed to set speaker: \(error.localizedDescription)")
        }
    }

    var availableRoutes: [AudioDevice] {
        let session = AVAudioSession.sharedInstance()
        var devices: [AudioDevice] = []

        // Built-in receiver (earpiece)
        devices.append(AudioDevice(id: "receiver", name: "iPhone", portType: .builtInReceiver))

        // Built-in speaker
        devices.append(AudioDevice(id: "speaker", name: "Speaker", portType: .builtInSpeaker))

        // Bluetooth devices
        for output in session.currentRoute.outputs {
            if output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP || output.portType == .bluetoothLE {
                devices.append(AudioDevice(id: output.uid, name: output.portName, portType: output.portType))
            }
        }

        return devices
    }
}
