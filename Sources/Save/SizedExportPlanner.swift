import Foundation

/// Chooses encode parameters so a clip lands under a byte budget — the
/// "make it fit Discord" export. Pure arithmetic; no AVFoundation.
///
/// Strategy (what Medal does implicitly): spend the budget on bitrate first,
/// and only step the resolution and frame rate down when the bitrate would
/// fall below what H.264 needs to look acceptable at that size.
public enum SizedExportPlanner {
    /// A preset byte budget for a sharing destination.
    public struct Target: Hashable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let bytes: Int64

        public init(id: String, title: String, bytes: Int64) {
            self.id = id
            self.title = title
            self.bytes = bytes
        }

        /// Discord's free upload limit (20 MB since 2026-09). Decimal
        /// megabytes are used on purpose: they are smaller than the binary
        /// ones Discord may count, so the file never lands just over.
        public static let discordFree = Target(id: "discord-20", title: "20 MB", bytes: 20_000_000)
        public static let discordNitroBasic = Target(id: "discord-50", title: "50 MB", bytes: 50_000_000)
        public static let hundredMB = Target(id: "100mb", title: "100 MB", bytes: 100_000_000)
        public static let discordNitro = Target(id: "discord-500", title: "500 MB", bytes: 500_000_000)

        public static let presets: [Target] = [.discordFree, .discordNitroBasic, .hundredMB, .discordNitro]
    }

    public struct Plan: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var frameRate: Int
        /// Bits per second for the video track.
        public var videoBitrate: Int
        /// Bits per second for the audio track (0 when the clip has no audio).
        public var audioBitrate: Int
        public var estimatedBytes: Int64
        /// False when even the smallest ladder rung can't fit the budget at
        /// the minimum acceptable quality; the export still runs at that rung.
        public var fitsTarget: Bool

        public var summary: String {
            let mbps = Double(videoBitrate) / 1_000_000
            let rate = mbps >= 10 ? String(format: "%.0f", mbps) : String(format: "%.1f", mbps)
            return "\(width)×\(height) · \(frameRate) fps · \(rate) Mbps"
        }
    }

    /// Fraction of the byte budget handed to the encoder. Covers MP4
    /// container overhead and average-bitrate overshoot.
    public static let safetyFactor = 0.90
    /// Container overhead applied when estimating the output size.
    public static let containerOverhead = 1.03
    /// Minimum H.264 bits per pixel per frame that still looks acceptable
    /// for game footage; below this we step the resolution / frame rate down.
    public static let minimumBitsPerPixel = 0.06
    /// Bits per pixel above which more bitrate buys nothing visible; caps
    /// generous budgets so a 10 s clip doesn't become a 500 MB file.
    public static let maximumBitsPerPixel = 0.20
    public static let minimumVideoBitrate = 250_000
    public static let maximumVideoBitrate = 50_000_000

    /// Heights we are willing to scale down to, largest first.
    static let heightLadder = [2160, 1440, 1080, 720, 540, 480, 360]

    public static func plan(
        durationSeconds: Double,
        sourceWidth: Int,
        sourceHeight: Int,
        sourceFrameRate: Double,
        targetBytes: Int64,
        hasAudio: Bool = true
    ) -> Plan {
        let duration = max(durationSeconds, 0.1)
        let sourceFPS = max(1, Int((sourceFrameRate.isFinite && sourceFrameRate > 0 ? sourceFrameRate : 30).rounded()))
        let budgetBits = Double(targetBytes) * 8 * safetyFactor
        let totalBitrate = budgetBits / duration

        let audioBitrate: Int
        if !hasAudio {
            audioBitrate = 0
        } else if totalBitrate < 800_000 {
            audioBitrate = 64_000
        } else if totalBitrate < 2_000_000 {
            audioBitrate = 96_000
        } else {
            audioBitrate = 128_000
        }

        let availableVideoBitrate = Int(totalBitrate) - audioBitrate
        var videoBitrate = min(max(availableVideoBitrate, minimumVideoBitrate), maximumVideoBitrate)

        // Candidate output sizes: the source itself, then the ladder below it.
        let aspect = sourceHeight > 0 ? Double(sourceWidth) / Double(sourceHeight) : 16.0 / 9.0
        var heights = heightLadder.filter { $0 < sourceHeight }
        heights.insert(min(sourceHeight, heightLadder[0]), at: 0)
        let frameRates = sourceFPS > 30 ? [sourceFPS, 30] : [sourceFPS]

        var chosen: (width: Int, height: Int, fps: Int)?
        search: for height in heights {
            let width = evenDimension(Double(height) * aspect)
            let evenHeight = evenDimension(Double(height))
            for fps in frameRates {
                let bitsPerPixel = Double(videoBitrate) / (Double(width * evenHeight) * Double(fps))
                if bitsPerPixel >= minimumBitsPerPixel {
                    chosen = (width, evenHeight, fps)
                    break search
                }
            }
        }

        let fits = chosen != nil
        if chosen == nil, let smallest = heights.last {
            let fps = frameRates.last ?? sourceFPS
            chosen = (evenDimension(Double(smallest) * aspect), evenDimension(Double(smallest)), fps)
        }
        let output = chosen ?? (evenDimension(Double(sourceWidth)), evenDimension(Double(sourceHeight)), sourceFPS)

        // Don't spend more than the picture can use.
        let ceiling = Int(maximumBitsPerPixel * Double(output.width * output.height) * Double(output.fps))
        videoBitrate = min(videoBitrate, max(ceiling, minimumVideoBitrate))

        let estimated = estimatedBytes(videoBitrate: videoBitrate, audioBitrate: audioBitrate, durationSeconds: duration)
        return Plan(
            width: output.width,
            height: output.height,
            frameRate: output.fps,
            videoBitrate: videoBitrate,
            audioBitrate: audioBitrate,
            estimatedBytes: estimated,
            fitsTarget: fits && estimated <= targetBytes
        )
    }

    public static func estimatedBytes(videoBitrate: Int, audioBitrate: Int, durationSeconds: Double) -> Int64 {
        Int64((Double(videoBitrate + audioBitrate) * max(durationSeconds, 0) / 8 * containerOverhead).rounded())
    }

    /// Longest clip that fits `targetBytes` at the given bitrates — the
    /// number to show next to a trim handle ("up to 1:12 at this size").
    public static func maximumDuration(targetBytes: Int64, videoBitrate: Int, audioBitrate: Int) -> Double {
        let bitrate = Double(videoBitrate + audioBitrate)
        guard bitrate > 0 else { return 0 }
        return Double(targetBytes) * 8 * safetyFactor / bitrate
    }

    /// Encoders want even dimensions; never below 2.
    static func evenDimension(_ value: Double) -> Int {
        max(2, Int((value / 2).rounded()) * 2)
    }
}
