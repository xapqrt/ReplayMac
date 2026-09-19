@preconcurrency import AVFoundation
import Foundation

public enum SizedExportError: Error, LocalizedError {
    case noVideoTrack
    case cannotStartReader(Error?)
    case cannotStartWriter(Error?)
    case readFailed(Error?)
    case writeFailed(Error?)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "The clip has no video track."
        case .cannotStartReader(let error): return "Couldn't read the clip: \(error?.localizedDescription ?? "unknown error")"
        case .cannotStartWriter(let error): return "Couldn't create the output file: \(error?.localizedDescription ?? "unknown error")"
        case .readFailed(let error): return "Reading the clip failed: \(error?.localizedDescription ?? "unknown error")"
        case .writeFailed(let error): return "Writing the export failed: \(error?.localizedDescription ?? "unknown error")"
        case .cancelled: return "Export cancelled."
        }
    }
}

/// Re-encodes a clip (or a range of it) to H.264/AAC at an exact average
/// bitrate, resolution and frame rate — what `AVAssetExportSession` presets
/// cannot do. Used for size-targeted exports ("fit in 20 MB for Discord").
///
/// H.264 rather than HEVC because that is what plays inline everywhere the
/// file is going to be pasted. Multiple audio tracks are mixed down to one
/// stereo AAC track; a video composition (crop) is honoured when supplied.
public final class SizedVideoExporter: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// - Parameters:
    ///   - progress: fraction of the time range written so far (0...1). Called
    ///     from a background queue.
    public func export(
        asset: AVAsset,
        timeRange: CMTimeRange,
        plan: SizedExportPlanner.Plan,
        videoComposition: AVVideoComposition?,
        to outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw SizedExportError.noVideoTrack
        }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let isHDR = try await videoTrack.load(.mediaCharacteristics).contains(.containsHDRVideo)

        try? FileManager.default.removeItem(at: outputURL)

        // The transcode loop is synchronous, blocking work; keep it off the
        // cooperative thread pool.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.transcode(
                        asset: asset,
                        videoTracks: videoTracks,
                        audioTracks: audioTracks,
                        preferredTransform: preferredTransform,
                        isHDR: isHDR,
                        timeRange: timeRange,
                        plan: plan,
                        videoComposition: videoComposition,
                        outputURL: outputURL,
                        progress: progress
                    )
                    continuation.resume()
                } catch {
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Synchronous pipeline

    /// Shared, queue-confined state for the two writer callbacks.
    private final class TranscodeState: @unchecked Sendable {
        var lastVideoSeconds: Double?
        var videoFinished = false
        var audioFinished = false
        private let lock = NSLock()
        private var storedFailure: Error?

        var failure: Error? {
            get { lock.lock(); defer { lock.unlock() }; return storedFailure }
            set { lock.lock(); storedFailure = newValue; lock.unlock() }
        }
    }

    private func transcode(
        asset: AVAsset,
        videoTracks: [AVAssetTrack],
        audioTracks: [AVAssetTrack],
        preferredTransform: CGAffineTransform,
        isHDR: Bool,
        timeRange: CMTimeRange,
        plan: SizedExportPlanner.Plan,
        videoComposition: AVVideoComposition?,
        outputURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw SizedExportError.cannotStartReader(error)
        }
        reader.timeRange = timeRange

        // 8-bit 4:2:0 in for the H.264 encoder; HDR sources are converted to
        // BT.709 on the way out of the decoder so the SDR output isn't washed out.
        var videoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        if isHDR {
            videoOutputSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        }

        let videoOutput: AVAssetReaderOutput
        if let videoComposition {
            let compositionOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: videoTracks,
                videoSettings: videoOutputSettings
            )
            compositionOutput.videoComposition = videoComposition
            videoOutput = compositionOutput
        } else {
            videoOutput = AVAssetReaderTrackOutput(track: videoTracks[0], outputSettings: videoOutputSettings)
        }
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw SizedExportError.cannotStartReader(nil)
        }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        if plan.audioBitrate > 0, !audioTracks.isEmpty {
            // nil settings = LPCM in a convenient format; all tracks mixed to one.
            let mixOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: nil)
            mixOutput.alwaysCopiesSampleData = false
            if reader.canAdd(mixOutput) {
                reader.add(mixOutput)
                audioOutput = mixOutput
            }
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw SizedExportError.cannotStartWriter(error)
        }
        writer.shouldOptimizeForNetworkUse = true

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: plan.width,
            AVVideoHeightKey: plan.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: plan.videoBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: plan.frameRate * 2,
                AVVideoExpectedSourceFrameRateKey: plan.frameRate,
                AVVideoAllowFrameReorderingKey: true
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        if videoComposition == nil {
            videoInput.transform = preferredTransform
        }
        guard writer.canAdd(videoInput) else {
            throw SizedExportError.cannotStartWriter(nil)
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: plan.audioBitrate
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            } else {
                audioOutput = nil
            }
        }

        guard reader.startReading() else {
            throw SizedExportError.cannotStartReader(reader.error)
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw SizedExportError.cannotStartWriter(writer.error)
        }
        writer.startSession(atSourceTime: timeRange.start)

        let state = TranscodeState()
        let group = DispatchGroup()
        let startSeconds = CMTimeGetSeconds(timeRange.start)
        let durationSeconds = max(CMTimeGetSeconds(timeRange.duration), 0.001)
        // Drop frames closer together than this to hit the planned frame rate
        // (with slack so 59.94 fps sources still pass at a 60 fps plan).
        let minimumFrameGap = (1.0 / Double(plan.frameRate)) * 0.9

        group.enter()
        let videoQueue = DispatchQueue(label: "com.replaycap.sized-export.video")
        videoInput.requestMediaDataWhenReady(on: videoQueue) { [self] in
            while videoInput.isReadyForMoreMediaData, !state.videoFinished {
                if isCancelled || state.failure != nil {
                    state.videoFinished = true
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                guard let sample = videoOutput.copyNextSampleBuffer() else {
                    state.videoFinished = true
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                if let last = state.lastVideoSeconds, seconds - last < minimumFrameGap {
                    continue // frame-rate reduction
                }
                state.lastVideoSeconds = seconds
                if !videoInput.append(sample) {
                    state.failure = SizedExportError.writeFailed(writer.error)
                    state.videoFinished = true
                    videoInput.markAsFinished()
                    group.leave()
                    return
                }
                progress(min(max((seconds - startSeconds) / durationSeconds, 0), 1))
            }
        }

        if let audioInput, let audioOutput {
            group.enter()
            let audioQueue = DispatchQueue(label: "com.replaycap.sized-export.audio")
            audioInput.requestMediaDataWhenReady(on: audioQueue) { [self] in
                while audioInput.isReadyForMoreMediaData, !state.audioFinished {
                    if isCancelled || state.failure != nil {
                        state.audioFinished = true
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                    guard let sample = audioOutput.copyNextSampleBuffer() else {
                        state.audioFinished = true
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                    if !audioInput.append(sample) {
                        state.failure = SizedExportError.writeFailed(writer.error)
                        state.audioFinished = true
                        audioInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }

        group.wait()

        if isCancelled {
            reader.cancelReading()
            writer.cancelWriting()
            throw SizedExportError.cancelled
        }
        if let failure = state.failure {
            reader.cancelReading()
            writer.cancelWriting()
            throw failure
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw SizedExportError.readFailed(reader.error)
        }

        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting {
            finished.signal()
        }
        finished.wait()

        guard writer.status == .completed else {
            throw SizedExportError.writeFailed(writer.error)
        }
        progress(1)
    }
}
