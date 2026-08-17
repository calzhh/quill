import AppKit
import Foundation
import QuillArtwork

@main
struct QuillIcon {
    private static let iconSizes: [(Int, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    static func main() {
        do {
            try run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("quill-icon: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func run(arguments: [String]) throws {
        guard arguments.count == 2, arguments[0] == "--output" else {
            throw GeneratorError.usage
        }

        let fileManager = FileManager.default
        let output = URL(fileURLWithPath: arguments[1])
        try fileManager.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let iconset = fileManager.temporaryDirectory
            .appendingPathComponent("quill-icon-\(UUID().uuidString).iconset")
        try fileManager.createDirectory(at: iconset, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: iconset) }

        guard let source = NSImage(data: Data(FeatherArtwork.svg.utf8)) else {
            throw GeneratorError.invalidArtwork
        }

        for (pixelSize, filename) in iconSizes {
            let representation = try rasterize(source, pixelSize: pixelSize)
            guard let png = representation.representation(using: .png, properties: [:]) else {
                throw GeneratorError.pngEncoding(filename)
            }
            try png.write(to: iconset.appendingPathComponent(filename), options: .atomic)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", "-o", output.path, iconset.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "unknown iconutil error"
            throw GeneratorError.iconutil(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func rasterize(_ source: NSImage, pixelSize: Int) throws -> NSBitmapImageRep {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else {
            throw GeneratorError.bitmapAllocation(pixelSize)
        }

        representation.size = NSSize(width: pixelSize, height: pixelSize)
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            throw GeneratorError.graphicsContext(pixelSize)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    private enum GeneratorError: LocalizedError {
        case usage
        case invalidArtwork
        case bitmapAllocation(Int)
        case graphicsContext(Int)
        case pngEncoding(String)
        case iconutil(String)

        var errorDescription: String? {
            switch self {
            case .usage:
                return "usage: quill-icon --output <path-to-AppIcon.icns>"
            case .invalidArtwork:
                return "could not decode the feather artwork"
            case let .bitmapAllocation(size):
                return "could not allocate a \(size)x\(size) bitmap"
            case let .graphicsContext(size):
                return "could not create a \(size)x\(size) graphics context"
            case let .pngEncoding(filename):
                return "could not encode \(filename) as PNG"
            case let .iconutil(message):
                return "iconutil failed: \(message)"
            }
        }
    }
}
