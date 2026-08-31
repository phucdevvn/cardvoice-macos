import CryptoKit
import Foundation

enum KokoroModelStore {
    enum ModelError: LocalizedError {
        case downloadFailed
        case checksumMismatch
        case extractionFailed(String)
        case incompleteModel

        var errorDescription: String? {
            switch self {
            case .downloadFailed:
                return "The Kokoro model download failed. Check your internet connection and try again."
            case .checksumMismatch:
                return "The downloaded Kokoro model failed its integrity check. Nothing was installed."
            case let .extractionFailed(message):
                return "Could not install the Kokoro model: \(message)"
            case .incompleteModel:
                return "The downloaded Kokoro model is incomplete. Nothing was installed."
            }
        }
    }

    static let version = "kokoro-en-v0_19"
    static let downloadURL = URL(
        string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2"
    )!
    static let archiveSHA256 = "912804855a04745fa77a30be545b3f9a5d15c4d66db00b88cbcd4921df605ac7"

    static func modelsFolder(fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = support
            .appending(path: "CardVoice", directoryHint: .isDirectory)
            .appending(path: "Models", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func modelDirectory(fileManager: FileManager = .default) throws -> URL {
        try modelsFolder(fileManager: fileManager)
            .appending(path: version, directoryHint: .isDirectory)
    }

    static func isInstalled(at directory: URL? = nil, fileManager: FileManager = .default) -> Bool {
        guard let directory = directory ?? (try? modelDirectory(fileManager: fileManager)) else { return false }
        let required = [
            directory.appending(path: "model.onnx"),
            directory.appending(path: "voices.bin"),
            directory.appending(path: "tokens.txt"),
            directory.appending(path: "espeak-ng-data/phontab")
        ]
        return required.allSatisfy { isRegularFile($0) }
    }

    static func install() async throws -> URL {
        let (archive, response) = try await URLSession.shared.download(from: downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelError.downloadFailed
        }
        guard try sha256(of: archive) == archiveSHA256 else {
            throw ModelError.checksumMismatch
        }

        let fileManager = FileManager.default
        let models = try modelsFolder(fileManager: fileManager)
        let staging = models.appending(path: ".install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try extract(archive: archive, into: staging)
        let extracted = staging.appending(path: version, directoryHint: .isDirectory)
        guard isInstalled(at: extracted, fileManager: fileManager) else {
            throw ModelError.incompleteModel
        }

        let destination = try modelDirectory(fileManager: fileManager)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: extracted, to: destination)
        return destination
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func extract(archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xjf", archive.path, "-C", directory.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ModelError.extractionFailed(message?.isEmpty == false ? message! : "archive extraction failed")
        }
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
