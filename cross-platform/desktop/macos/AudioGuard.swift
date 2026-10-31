import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

// This helper owns one AudioQueue pinned to a CoreAudio device UID.
// It has no UI or network interface; the MyGo host speaks JSON over stdin.
struct OutputRoute: Codable {
    let connected: Bool
    let verified: Bool
    let name: String
    let token: String
    let requiresConfirmation: Bool
}
enum GuardError: Error { case invalidSound, noHeadphones, audio(OSStatus), invalidMedia, invalidCommand, mediaProbe(String) }
func check(_ status: OSStatus) throws { if status != noErr { throw GuardError.audio(status) } }

final class AudioGuard {
    let serial = DispatchQueue(label: "com.hushnest.audio")
    let audioDirectory: URL
    let mediaDirectory: URL
    var output: AudioQueueRef?
    var reader: AVAssetReader?
    var trackOutput: AVAssetReaderTrackOutput?
    var source: URL?
    var sourceAlias: URL?
    var sourceLimit = Double.infinity
    var pending = Data()
    var pendingOffset = 0
    var selectedToken = ""
    var confirmedToken = ""
    var previewEnd = Date.distantFuture
    var timer: DispatchSourceTimer?
    let bufferBytes: UInt32 = 4800 * 2 * 4

    init(audio: URL, media: URL) {
        audioDirectory = audio; mediaDirectory = media
        // A crash may leave a decoder hard link behind. Remove only our own
        // UUID-named aliases, never the canonical imported media files.
        for file in (try? FileManager.default.contentsOfDirectory(at: media, includingPropertiesForKeys: nil)) ?? [] {
            let name = file.deletingPathExtension().lastPathComponent
            if name.hasPrefix(".decode-"), UUID(uuidString: String(name.dropFirst(8))) != nil,
               ["wav", "aiff", "caf", "flac", "ogg", "aac", "mp3", "mp4", "mov"].contains(file.pathExtension) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
    // AVFoundation relies on a recognizable URL extension on macOS 12/13.
    // Detect the container from its bytes and make a temporary private hard
    // link: no full-file copy, no user-controlled extension or external path.
    func decoderURL(_ stored: URL) throws -> URL {
        guard stored.pathExtension == "media" else { return stored }
        let file = try FileHandle(forReadingFrom: stored)
        defer { try? file.close() }
        let bytes = Array(try file.read(upToCount: 32) ?? Data())
        func tag(_ offset: Int, _ length: Int) -> String {
            guard bytes.count >= offset + length else { return "" }
            return String(bytes: bytes[offset..<(offset + length)], encoding: .ascii) ?? ""
        }
        let ext: String
        if ["RIFF", "RF64", "BW64"].contains(tag(0, 4)) && tag(8, 4) == "WAVE" { ext = "wav" }
        else if tag(0, 4) == "FORM" && ["AIFF", "AIFC"].contains(tag(8, 4)) { ext = "aiff" }
        else if tag(0, 4) == "caff" { ext = "caf" }
        else if tag(0, 4) == "fLaC" { ext = "flac" }
        else if tag(0, 4) == "OggS" { ext = "ogg" }
        else if tag(4, 4) == "ftyp" { ext = tag(8, 4) == "qt  " ? "mov" : "mp4" }
        else if ["moov", "mdat", "wide"].contains(tag(4, 4)) { ext = "mov" }
        else if tag(0, 4) == "ADIF" || bytes.count >= 2 && bytes[0] == 0xff && bytes[1] & 0xf6 == 0xf0 { ext = "aac" }
        else if tag(0, 3) == "ID3" || bytes.count >= 2 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0 { ext = "mp3" }
        else { throw GuardError.mediaProbe("unsupported-container") }
        let alias = mediaDirectory.appendingPathComponent(".decode-" + UUID().uuidString + "." + ext)
        try FileManager.default.linkItem(at: stored, to: alias)
        return alias
    }
    func inspect(_ id: String) throws -> Double {
        let url = try decoderURL(mediaDirectory.appendingPathComponent(id + ".media"))
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let seconds = asset.duration.seconds
        guard seconds.isFinite && seconds > 0 && !asset.hasProtectedContent else { throw GuardError.mediaProbe("invalid-duration-or-protected") }
        guard let track = asset.tracks(withMediaType: .audio).first else { throw GuardError.mediaProbe("missing-audio-track") }
        let probe = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard probe.canAdd(output) else { throw GuardError.mediaProbe("unsupported-audio-track") }; probe.add(output)
        guard probe.startReading() else { throw probe.error ?? GuardError.mediaProbe("decoder-start") }
        defer { probe.cancelReading() }
        guard output.copyNextSampleBuffer() != nil else { throw probe.error ?? GuardError.mediaProbe("decoder-empty") }
        return seconds
    }
    func emit(_ value: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(value), let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        FileHandle.standardOutput.write(bytes); FileHandle.standardOutput.write(Data([10]))
    }
    func uintProperty(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    func stringProperty(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return "" }
        return value as String
    }
    func route() -> OutputRoute {
        let empty = OutputRoute(connected: false, verified: false, name: "", token: "", requiresConfirmation: false)
        guard let device = uintProperty(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice), device != kAudioObjectUnknown,
              uintProperty(device, kAudioDevicePropertyDeviceIsAlive) == 1,
              let transport = uintProperty(device, kAudioDevicePropertyTransportType) else { return empty }
        let uid = stringProperty(device, kAudioDevicePropertyDeviceUID)
        guard !uid.isEmpty else { return empty }
        let name = stringProperty(device, kAudioObjectPropertyName)
        let wired = transport == kAudioDeviceTransportTypeBuiltIn && uintProperty(device, kAudioDevicePropertyJackIsConnected, scope: kAudioDevicePropertyScopeOutput) == 1
        let needsConfirmation = transport == kAudioDeviceTransportTypeUSB || transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        return OutputRoute(connected: wired || needsConfirmation && confirmedToken == uid, verified: wired, name: name, token: uid, requiresConfirmation: needsConfirmation)
    }
    func stop() {
        let old = output; output = nil
        if let old { AudioQueueSetParameter(old, kAudioQueueParam_Volume, 0); AudioQueueStop(old, true); AudioQueueDispose(old, true) }
        reader?.cancelReading(); reader = nil; trackOutput = nil; source = nil
        if let alias = sourceAlias { try? FileManager.default.removeItem(at: alias) }; sourceAlias = nil
        selectedToken = ""; previewEnd = .distantFuture; pending.removeAll(keepingCapacity: false); pendingOffset = 0
    }
    func lost() {
        stop(); confirmedToken = ""; emit(["eventType": "routeLost"])
    }
    func resetReader() throws {
        guard let source else { throw GuardError.invalidMedia }
        reader?.cancelReading()
        let asset = AVURLAsset(url: source)
        guard let track = asset.tracks(withMediaType: .audio).first else { throw GuardError.invalidMedia }
        let next = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
            AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard next.canAdd(output) else { throw GuardError.invalidMedia }; next.add(output)
        if sourceLimit.isFinite { next.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: sourceLimit, preferredTimescale: 48000)) }
        guard next.startReading() else { throw next.error ?? GuardError.invalidMedia }
        reader = next; trackOutput = output
    }
    func nextChunk() throws -> Data {
        for attempt in 0..<2 {
            if let sample = trackOutput?.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
                let length = CMBlockBufferGetDataLength(block)
                guard length > 0 && length <= 4 * 1024 * 1024 else { throw GuardError.invalidMedia }
                var bytes = Data(count: length)
                try bytes.withUnsafeMutableBytes { p in try check(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: p.baseAddress!)) }
                return bytes
            }
            if reader?.status == .failed { throw reader?.error ?? GuardError.invalidMedia }
            if attempt == 0 { try resetReader() }
        }
        throw GuardError.invalidMedia
    }
    func fill(_ queue: AudioQueueRef, _ buffer: AudioQueueBufferRef) throws {
        guard output == queue else { return }
        var written = 0; let capacity = Int(buffer.pointee.mAudioDataBytesCapacity)
        while written < capacity {
            if pendingOffset >= pending.count { pending = try nextChunk(); pendingOffset = 0 }
            let count = min(capacity - written, pending.count - pendingOffset)
            pending.withUnsafeBytes { p in buffer.pointee.mAudioData.advanced(by: written).copyMemory(from: p.baseAddress!.advanced(by: pendingOffset), byteCount: count) }
            pendingOffset += count; written += count
        }
        buffer.pointee.mAudioDataByteSize = UInt32(written)
        try check(AudioQueueEnqueueBuffer(queue, buffer, 0, nil))
    }
    func play(_ input: [String: Any]) throws {
        stop(); let current = route()
        guard current.connected else { throw GuardError.noHeadphones }
        guard let sound = input["sound"] as? String else { throw GuardError.invalidSound }
        let custom = sound.hasPrefix("custom:")
        if custom {
            let id = String(sound.dropFirst(7)); guard UUID(uuidString: id) != nil && id.count == 36 else { throw GuardError.invalidSound }
            sourceAlias = try decoderURL(mediaDirectory.appendingPathComponent(id + ".media")); source = sourceAlias
        } else {
            let allowed = Set("rain ocean stream forest fireplace night brown pink dawn bell orbit piano marimba harp bamboo aurora classic twinbell digital pulse beacon reveille".split(separator: " ").map(String.init))
            guard allowed.contains(sound) else { throw GuardError.invalidSound }; source = audioDirectory.appendingPathComponent(sound + ".wav")
        }
        sourceLimit = custom && input["alarm"] as? Bool == true ? 60 : .infinity
        try resetReader()
        var format = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var queue: AudioQueueRef?
        try check(AudioQueueNewOutputWithDispatchQueue(&queue, &format, 0, serial) { [weak self] queue, buffer in
            guard let self else { return }
            do { try self.fill(queue, buffer) }
            catch { AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0); self.serial.async { self.lost() } }
        })
        guard let queue else { throw GuardError.invalidMedia }; output = queue
        try check(AudioQueueSetParameter(queue, kAudioQueueParam_Volume, 0))
        var uid = current.token as CFString
        try check(AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &uid, UInt32(MemoryLayout<CFString>.size)))
        var actual: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size)
        try check(AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentDevice, &actual, &size))
        guard actual as String == current.token else { throw GuardError.noHeadphones }
        selectedToken = current.token
        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?; try check(AudioQueueAllocateBuffer(queue, bufferBytes, &buffer))
            guard let buffer else { throw GuardError.invalidMedia }; try fill(queue, buffer)
        }
        let verified = route(); guard verified.connected && verified.token == selectedToken else { throw GuardError.noHeadphones }
        let volume = max(0, min(1, input["volume"] as? Double ?? 0.1))
        try check(AudioQueueSetParameter(queue, kAudioQueueParam_Volume, Float(volume)))
        try check(AudioQueueStart(queue, nil))
        if input["preview"] as? Bool == true { previewEnd = Date().addingTimeInterval(2) }
    }
    func handle(_ bytes: Data) {
        var id: Int64 = 0
        do {
            guard let input = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let action = input["action"] as? String else { throw GuardError.invalidCommand }
            id = (input["id"] as? NSNumber)?.int64Value ?? 0
            var result: Any = NSNull()
            switch action {
            case "route": result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(route()))
            case "inspect":
                guard let sound = input["sound"] as? String, sound.hasPrefix("custom:") else { throw GuardError.invalidMedia }
                let id = String(sound.dropFirst(7))
                guard UUID(uuidString: id) != nil && id.count == 36 else { throw GuardError.invalidMedia }
                result = ["seconds": try inspect(id)]
            case "confirmRoute":
                let current = route(); guard current.requiresConfirmation && !current.token.isEmpty else { throw GuardError.noHeadphones }; confirmedToken = current.token
            case "play": try play(input)
            case "stop": stop()
            case "volume": if let output { try check(AudioQueueSetParameter(output, kAudioQueueParam_Volume, Float(max(0, min(1, input["value"] as? Double ?? 0))))) }
            default: throw GuardError.invalidCommand
            }
            emit(["id": id, "result": result, "error": NSNull()])
        } catch { stop(); emit(["id": id, "error": String(describing: error)]) }
    }
    func start() {
        let monitor = DispatchSource.makeTimerSource(queue: serial); timer = monitor
        monitor.schedule(deadline: .now(), repeating: .milliseconds(100))
        monitor.setEventHandler { [weak self] in
            guard let self, self.output != nil else { return }
            if Date() >= self.previewEnd { self.stop(); return }
            let current = self.route()
            if !current.connected || current.token != self.selectedToken { self.lost() }
        }
        monitor.resume()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            while let line = readLine() { if let bytes = line.data(using: .utf8) { serial.async { self.handle(bytes) } } }
            serial.async { self.stop(); exit(0) }
        }
    }
}

guard CommandLine.arguments.count == 3 else { exit(2) }
let audioGuard = AudioGuard(audio: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true), media: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
audioGuard.start()
dispatchMain()
