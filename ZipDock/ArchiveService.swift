import Foundation
import ZIPFoundation

struct OutputFile: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var size: String {
        let count = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

enum ArchiveError: LocalizedError {
    case invalidParts, emptyInput, invalidChunkSize, invalidZIP
    var errorDescription: String? {
        switch self {
        case .invalidParts: return "Выбери все части одного файла: .part001, .part002 и так далее — без пропусков."
        case .emptyInput: return "Файл пуст или недоступен."
        case .invalidChunkSize: return "Недопустимый размер части."
        case .invalidZIP: return "Для распаковки нужен ZIP-файл."
        }
    }
}

final class ArchiveService {
    static let shared = ArchiveService()
    private let fm = FileManager.default
    private init() {}

    private var documents: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private var outputFolder: URL {
        let url = documents.appendingPathComponent("Результаты", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func importedCopy(_ source: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir) else { throw ArchiveError.emptyInput }
        let batch = documents.appendingPathComponent("Импорт", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dest = batch.appendingPathComponent(source.lastPathComponent)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: dest)
        return dest
    }

    func uniqueURL(in dir: URL, name: String) -> URL {
        let initial = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: initial.path) else { return initial }
        let ext = initial.pathExtension
        let stem = initial.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let candidate = dir.appendingPathComponent("\(stem)-\(n)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    func zip(_ source: URL) throws -> [OutputFile] {
        let destination = uniqueURL(in: outputFolder, name: source.lastPathComponent + ".zip")
        try fm.zipItem(at: source, to: destination, compressionMethod: .deflate)
        return [OutputFile(url: destination)]
    }

    func unzip(_ source: URL) throws -> [OutputFile] {
        guard source.pathExtension.lowercased() == "zip" else { throw ArchiveError.invalidZIP }
        let dest = uniqueURL(in: outputFolder, name: source.deletingPathExtension().lastPathComponent + "-распаковано")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        do {
            try fm.unzipItem(at: source, to: dest)
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }
        return [OutputFile(url: dest)]
    }

    // Части — обычные последовательные байты, НЕ многотомный ZIP.
    // Собираются назад без изменений и подходят для передачи большого IPA.
    func split(_ source: URL, megabytes: Int) throws -> [OutputFile] {
        guard megabytes > 0 else { throw ArchiveError.invalidChunkSize }
        let chunkSize = Int64(megabytes) * 1024 * 1024
        let attributes = try fm.attributesOfItem(atPath: source.path)
        guard let length = (attributes[.size] as? NSNumber)?.int64Value, length > 0 else { throw ArchiveError.emptyInput }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let count = Int((length + chunkSize - 1) / chunkSize)
        let digits = max(3, String(count).count)
        let batch = uniqueURL(in: outputFolder, name: source.lastPathComponent + "-части")
        try fm.createDirectory(at: batch, withIntermediateDirectories: true)
        var created: [URL] = []
        do {
            for index in 1...count {
                let suffix = String(format: "%0*d", digits, index)
                let name = source.lastPathComponent + ".part" + suffix
                let destination = batch.appendingPathComponent(name)
                guard fm.createFile(atPath: destination.path, contents: nil) else { throw ArchiveError.emptyInput }
                created.append(destination)
                let output = try FileHandle(forWritingTo: destination)
                defer { try? output.close() }
                var remaining = min(chunkSize, length - Int64(index - 1) * chunkSize)
                while remaining > 0 {
                    let block = try input.read(upToCount: Int(min(remaining, 1024 * 1024))) ?? Data()
                    if block.isEmpty { throw ArchiveError.emptyInput }
                    try output.write(contentsOf: block)
                    remaining -= Int64(block.count)
                }
            }
        } catch {
            try? fm.removeItem(at: batch)
            throw error
        }
        return created.map { OutputFile(url: $0) }
    }

    func join(_ files: [URL]) throws -> [OutputFile] {
        guard !files.isEmpty else { throw ArchiveError.invalidParts }
        let sorted = files.sorted { partNumber($0) < partNumber($1) }
        guard let name = baseName(sorted[0]), partNumber(sorted[0]) == 1 else { throw ArchiveError.invalidParts }
        for (index, file) in sorted.enumerated() {
            guard baseName(file) == name, partNumber(file) == index + 1 else { throw ArchiveError.invalidParts }
        }
        let destination = uniqueURL(in: outputFolder, name: name)
        guard fm.createFile(atPath: destination.path, contents: nil) else { throw ArchiveError.emptyInput }
        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            for file in sorted {
                let input = try FileHandle(forReadingFrom: file)
                defer { try? input.close() }
                while true {
                    let block = try input.read(upToCount: 1024 * 1024) ?? Data()
                    if block.isEmpty { break }
                    try output.write(contentsOf: block)
                }
            }
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
        return [OutputFile(url: destination)]
    }

    private func partNumber(_ url: URL) -> Int {
        guard let range = url.lastPathComponent.range(of: #"\.part[0-9]+$"#, options: .regularExpression) else { return -1 }
        return Int(url.lastPathComponent[range].dropFirst(5)) ?? -1
    }
    private func baseName(_ url: URL) -> String? {
        guard let range = url.lastPathComponent.range(of: #"\.part[0-9]+$"#, options: .regularExpression) else { return nil }
        return String(url.lastPathComponent[..<range.lowerBound])
    }
}
