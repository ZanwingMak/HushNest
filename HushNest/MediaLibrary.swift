@preconcurrency import AVFoundation
import Combine
import CoreTransferable
import UniformTypeIdentifiers

struct PersonalSound: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let duration: Double

    /// 使用受控文件名定位本机音轨，名称不参与路径拼接。
    func url(in directory: URL, alarm: Bool = false) -> URL {
        directory.appendingPathComponent(id.uuidString + (alarm ? "-alarm.m4a" : ".m4a"))
    }
}

enum MediaFailure: LocalizedError {
    case invalid, tooLarge, full, exportFailed
    var errorDescription: String? {
        switch self {
        case .invalid: L("请选择含有可播放音轨的音频或视频，不支持受保护或损坏的文件。")
        case .tooLarge: L("单个文件最多 200 MB，音轨时长需为 1 秒至 2 小时。")
        case .full: L("最多保存 20 个自定义声音，请先删除不再使用的声音。")
        case .exportFailed: L("无法提取音轨，请检查文件和剩余存储空间后重试。")
        }
    }
}

@MainActor
final class MediaLibrary: ObservableObject {
    nonisolated static var directory: URL { URL.applicationSupportDirectory.appendingPathComponent("PersonalSounds", isDirectory: true) }
    @Published private(set) var sounds: [PersonalSound] = []
    let directory: URL

    /// 恢复本机媒体清单，测试可注入隔离目录。
    init(directory: URL = MediaLibrary.directory) {
        self.directory = directory
        if let data = try? Data(contentsOf: directory.appendingPathComponent("library.json")),
           let saved = try? JSONDecoder().decode([PersonalSound].self, from: data) { sounds = saved }
    }

    /// 校验媒体后提取 M4A；铃声使用前 60 秒，两份文件和清单一起提交。
    func importFile(_ source: URL, name: String? = nil) async throws -> PersonalSound {
        guard sounds.count < 20 else { throw MediaFailure.full }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 200 * 1024 * 1024 else { throw MediaFailure.tooLarge }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, (1...7200).contains(duration) else { throw MediaFailure.tooLarge }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty, try await asset.load(.isPlayable), !(try await asset.load(.hasProtectedContent)) else { throw MediaFailure.invalid }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sound = PersonalSound(id: UUID(), name: String((name ?? source.deletingPathExtension().lastPathComponent).prefix(80)), duration: duration)
        let full = sound.url(in: directory), alarm = sound.url(in: directory, alarm: true)
        do {
            try await export(asset, to: full, duration: duration)
            try await export(asset, to: alarm, duration: min(60, duration))
            try Task.checkCancellation()
            // 防止并发导入绕过上限，保存失败时也不留下孤立音轨。
            guard sounds.count < 20 else { throw MediaFailure.full }
            let updated = sounds + [sound]
            try save(updated)
            sounds = updated
            return sound
        } catch {
            try? FileManager.default.removeItem(at: full)
            try? FileManager.default.removeItem(at: alarm)
            throw error
        }
    }

    /// 先持久化新清单再删除文件，防止失败时界面与磁盘状态不一致。
    func remove(_ sound: PersonalSound) throws {
        let updated = sounds.filter { $0.id != sound.id }
        try save(updated)
        sounds = updated
        try? FileManager.default.removeItem(at: sound.url(in: directory))
        try? FileManager.default.removeItem(at: sound.url(in: directory, alarm: true))
    }

    /// 原子写入媒体清单，文件仅保存在应用沙盒内。
    private func save(_ sounds: [PersonalSound]) throws {
        try JSONEncoder().encode(sounds).write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    }

    /// 异步转码并响应取消，不播放视频或请求麦克风权限。
    private func export(_ asset: AVAsset, to url: URL, duration: Double) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw MediaFailure.exportFailed }
        exporter.outputURL = url
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
        await withTaskCancellationHandler {
            await exporter.export()
        } onCancel: { exporter.cancelExport() }
        try Task.checkCancellation()
        guard exporter.status == .completed else { throw MediaFailure.exportFailed }
    }
}

struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let target = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: target)
            return ImportedMovie(url: target)
        }
    }
}
