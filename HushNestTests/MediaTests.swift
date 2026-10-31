import XCTest
import AVFoundation
import UIKit
@testable import HushNest

@MainActor
final class MediaTests: XCTestCase {
    private var directory: URL!

    /// 为每个媒体用例创建独立目录，全程只转码和解码，不播放音频。
    override func setUp() async throws {
        directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 删除本用例生成的媒体与清单，避免累积模拟器文件。
    override func tearDown() async throws { try FileManager.default.removeItem(at: directory) }

    /// 音频导入可跨实例恢复；文件名与展示名隔离，删除后两条音轨均消失。
    func testAudioImportPersistenceAndDeletion() async throws {
        let library = MediaLibrary(directory: directory.appendingPathComponent("library"))
        let source = try XCTUnwrap(HeadphoneAudio.bundledURL(named: "rain"))
        let sound = try await library.importFile(source, name: "../../my rain")
        XCTAssertEqual(sound.name, "../../my rain")
        XCTAssertEqual(library.sounds.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sound.url(in: library.directory).path))
        let restored = MediaLibrary(directory: library.directory)
        XCTAssertEqual(restored.sounds, [sound])
        let file = try AVAudioFile(forReading: sound.url(in: library.directory))
        XCTAssertGreaterThan(file.length, 1_000_000)
        try restored.remove(sound)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sound.url(in: library.directory).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sound.url(in: library.directory, alarm: true).path))
        XCTAssertTrue(MediaLibrary(directory: library.directory).sounds.isEmpty)
    }

    /// 用真实播放层读取导入后的两种用途音轨，但不启动扬声器或耳机播放。
    func testImportedSoundsResolveInRealAudioLayer() async throws {
        let library = MediaLibrary()
        let source = try XCTUnwrap(Bundle.main.url(forResource: "bell", withExtension: "wav"))
        let sound = try await library.importFile(source, name: "Playback route fixture")
        defer { try? library.remove(sound) }
        let audio = HeadphoneAudio()
        defer { audio.stop() }
        for role in ["sleep", "alarm"] {
            let player = try audio.preparePreview(name: "custom-\(role).\(sound.id.uuidString)", volume: 0.2)
            XCTAssertGreaterThan(player.duration, 59)
            XCTAssertFalse(player.isPlaying)
            audio.updatePreviewVolume(0.6)
            XCTAssertEqual(player.volume, 0.6, accuracy: 0.001)
        }
        XCTAssertThrowsError(try audio.preparePreview(name: "custom-alarm." + UUID().uuidString, volume: 0.2))
        XCTAssertThrowsError(try audio.preparePreview(name: "custom-sleep.../../rain", volume: 0.2))
    }

    /// 长音轨保留完整助眠长度，并把独立铃声限制为前六十秒。
    func testCustomAlarmIsTrimmedToSixtySeconds() async throws {
        let source = directory.appendingPathComponent("long.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        var file: AVAudioFile? = try AVAudioFile(forWriting: source, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22050 * 65)!
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][index] = Float(sin(Double(index) * .pi * 2 * 440 / 22050)) * 0.2 }
        try file!.write(from: buffer)
        file = nil
        let library = MediaLibrary(directory: directory.appendingPathComponent("library"))
        let sound = try await library.importFile(source)
        XCTAssertEqual(sound.duration, 65, accuracy: 0.1)
        let asset = AVURLAsset(url: sound.url(in: library.directory, alarm: true))
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 60, accuracy: 0.1)
    }

    /// 真正的视频轨与音频轨可导入，输出只包含音轨而不包含视频。
    func testVideoExtractsOnlyAudio() async throws {
        let movie = try await makeMovie(withAudio: true)
        let library = MediaLibrary(directory: directory.appendingPathComponent("library"))
        let sound = try await library.importFile(movie)
        let asset = AVURLAsset(url: sound.url(in: library.directory))
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(audio.count, 1)
        XCTAssertTrue(video.isEmpty)
    }

    /// 无音轨视频和损坏数据均不能进入媒体清单。
    func testRejectsSilentVideoAndCorruptedFile() async throws {
        let library = MediaLibrary(directory: directory.appendingPathComponent("library"))
        let movie = try await makeMovie(withAudio: false)
        do { _ = try await library.importFile(movie); XCTFail("Silent movie must fail") } catch {}
        let broken = directory.appendingPathComponent("broken.mp3")
        try Data("not audio".utf8).write(to: broken)
        do { _ = try await library.importFile(broken); XCTFail("Corrupt media must fail") } catch {}
        XCTAssertTrue(library.sounds.isEmpty)
    }

    /// 已取消任务不写入音轨或清单，超大文件也应在解码前拒绝。
    func testCancellationAndSizeLimit() async throws {
        let library = MediaLibrary(directory: directory.appendingPathComponent("library"))
        let source = try XCTUnwrap(HeadphoneAudio.bundledURL(named: "rain"))
        let task = Task { try await library.importFile(source) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled import must fail") } catch {}
        XCTAssertTrue(library.sounds.isEmpty)
        let large = directory.appendingPathComponent("large.wav")
        FileManager.default.createFile(atPath: large.path, contents: nil)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 201 * 1024 * 1024)
        try handle.close()
        do { _ = try await library.importFile(large); XCTFail("Oversize media must fail") }
        catch { XCTAssertTrue(error is MediaFailure) }
    }

    /// 构造最小真实视频，再按需混入内置音频以覆盖视频提取链路。
    private func makeMovie(withAudio: Bool) async throws -> URL {
        let silent = directory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var pixel: CVPixelBuffer?
        CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32ARGB, nil, &pixel)
        let buffer = try XCTUnwrap(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 100, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(adaptor.append(buffer, withPresentationTime: .zero))
        writer.endSession(atSourceTime: CMTime(seconds: 2, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        guard withAudio else { return silent }
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent)
        let video = try await videoAsset.loadTracks(withMediaType: .video)[0]
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)), of: video, at: .zero)
        let audioAsset = AVURLAsset(url: try XCTUnwrap(HeadphoneAudio.bundledURL(named: "rain")))
        let audio = try await audioAsset.loadTracks(withMediaType: .audio)[0]
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)), of: audio, at: .zero)
        let output = directory.appendingPathComponent("with-audio.mov")
        let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        exporter.outputURL = output
        exporter.outputFileType = .mov
        await exporter.export()
        XCTAssertEqual(exporter.status, .completed)
        return output
    }
}
