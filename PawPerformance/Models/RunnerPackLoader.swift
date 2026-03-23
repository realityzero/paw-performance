import AppKit
import Foundation

enum RunnerPackLoaderError: Error {
    case runnersDirectoryMissing
}

final class RunnerPackLoader {
    func loadPacks() throws -> [RunnerPack] {
        guard let runnersURL = resolveRunnersDirectoryURL() else {
            throw RunnerPackLoaderError.runnersDirectoryMissing
        }

        let fileManager = FileManager.default
        let candidateURLs = try fileManager.contentsOfDirectory(
            at: runnersURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let packs = try candidateURLs.compactMap { url -> RunnerPack? in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return nil }
            return try loadPack(from: url)
        }

        return packs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func resolveRunnersDirectoryURL() -> URL? {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "Runners", withExtension: nil),
            Bundle.module.resourceURL?.appendingPathComponent("Runners"),
            Bundle.module.resourceURL?.appendingPathComponent("Resources/Runners"),
            Bundle.main.resourceURL?.appendingPathComponent("Runners"),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/Runners")
        ]

        let fileManager = FileManager.default
        for candidate in candidates.compactMap({ $0 }) {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    private func loadPack(from directoryURL: URL) throws -> RunnerPack {
        let metadataURL = directoryURL.appendingPathComponent("metadata.json")
        let metadataData = try Data(contentsOf: metadataURL)
        let metadata = try JSONDecoder().decode(RunnerPackMetadata.self, from: metadataData)

        let frameSize = CGSize(width: metadata.frameSize.width, height: metadata.frameSize.height)
        var framesByState: [RunnerState: [NSImage]] = [:]

        for state in RunnerState.allCases {
            let spec = metadata.states[state]
            let frameCount = max(1, spec?.frames ?? 1)
            let stripURL = directoryURL.appendingPathComponent("\(state.rawValue).png")

            if let stripImage = NSImage(contentsOf: stripURL),
               let sliced = sliceStrip(stripImage, frameCount: frameCount, frameSize: frameSize),
               !sliced.isEmpty {
                framesByState[state] = sliced
            } else {
                framesByState[state] = fallbackFrames(for: metadata.id, state: state, count: frameCount)
            }
        }

        return RunnerPack(
            id: metadata.id,
            name: metadata.name,
            speedMultiplier: metadata.speedMultiplier ?? 1.0,
            frameSize: frameSize,
            framesByState: framesByState
        )
    }

    private func sliceStrip(_ image: NSImage, frameCount: Int, frameSize: CGSize) -> [NSImage]? {
        let cgImage: CGImage? = image.representations
            .lazy
            .compactMap { ($0 as? NSBitmapImageRep)?.cgImage }
            .first

        guard let cgImage else { return nil }

        var output: [NSImage] = []
        output.reserveCapacity(frameCount)
        let totalWidth = cgImage.width
        let totalHeight = cgImage.height
        let targetWidth = Int(frameSize.width)
        let targetHeight = Int(frameSize.height)

        guard totalHeight >= targetHeight else { return nil }

        let y = max(0, totalHeight - targetHeight)
        for index in 0 ..< frameCount {
            let x = index * targetWidth
            guard x + targetWidth <= totalWidth else { break }
            let rect = CGRect(x: x, y: y, width: targetWidth, height: targetHeight)
            guard let cropped = cgImage.cropping(to: rect) else { continue }
            let frame = NSImage(cgImage: cropped, size: frameSize)
            frame.isTemplate = true
            output.append(frame)
        }

        return output
    }

    private func fallbackFrames(for packID: String, state: RunnerState, count: Int) -> [NSImage] {
        let symbolBase: String = {
            if packID.lowercased().contains("dog") { return "dog" }
            return "cat"
        }()

        let symbolName: String = {
            switch state {
            case .idle:
                return "\(symbolBase)"
            case .trot:
                return "\(symbolBase).fill"
            case .sprint:
                return "bolt.fill"
            case .panic:
                return "flame.fill"
            }
        }()

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true

        return Array(repeating: image, count: max(1, count))
    }
}
