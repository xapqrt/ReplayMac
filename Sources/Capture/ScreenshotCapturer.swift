import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

public enum ScreenshotError: Error, CustomStringConvertible {
    case noDisplay
    case encodingFailed

    public var description: String {
        switch self {
        case .noDisplay: return "No display is available to capture."
        case .encodingFailed: return "The screenshot could not be encoded as PNG."
        }
    }
}

/// One-shot, full-resolution stills of a display via ScreenCaptureKit —
/// the Medal "screenshot hotkey". Independent of the replay pipeline so it
/// works whether or not recording is running.
public enum ScreenshotCapturer {
    /// Captures a display and writes it as PNG. Returns the file URL.
    ///
    /// Display choice, in order: `preferredDisplayID` (the display the replay
    /// pipeline is recording), the display under the mouse, the main display.
    /// The image never leaves this function, so callers on any actor can
    /// await it without crossing a non-Sendable `CGImage`.
    public static func capturePNG(
        preferredDisplayID: CGDirectDisplayID?,
        directory: URL,
        baseName: String,
        showsCursor: Bool = false
    ) async throws -> URL {
        let content = try await CapturePermissions().requestAccess(interactive: true)
        let mouseDisplayID = displayUnderMouse()
        let mainDisplayID = CGMainDisplayID()

        let display = content.displays.first { CGDirectDisplayID($0.displayID) == preferredDisplayID }
            ?? content.displays.first { CGDirectDisplayID($0.displayID) == mouseDisplayID }
            ?? content.displays.first { CGDirectDisplayID($0.displayID) == mainDisplayID }
            ?? content.displays.first
        guard let display else {
            throw ScreenshotError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let scale = max(Double(filter.pointPixelScale), 1.0)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((Double(display.width) * scale).rounded())
        configuration.height = Int((Double(display.height) * scale).rounded())
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = uniqueURL(in: directory, baseName: baseName)
        try writePNG(image, to: url)
        return url
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotError.encodingFailed
        }
    }

    static func uniqueURL(in directory: URL, baseName: String) -> URL {
        var url = directory.appendingPathComponent("\(baseName).png")
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(baseName)_\(counter).png")
            counter += 1
        }
        return url
    }

    /// The display containing the mouse pointer, in CoreGraphics global
    /// coordinates (top-left origin, the same space `CGEvent` reports).
    static func displayUnderMouse() -> CGDirectDisplayID? {
        guard let location = CGEvent(source: nil)?.location else {
            return nil
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let result = CGGetDisplaysWithPoint(location, UInt32(displays.count), &displays, &count)
        guard result == .success, count > 0 else {
            return nil
        }
        return displays[0]
    }
}
