import XCTest
@testable import Save

final class SizedExportPlannerTests: XCTestCase {
    private let twentyMB: Int64 = 20_000_000

    func testShortClipKeepsFullResolutionAndFrameRate() {
        let plan = SizedExportPlanner.plan(
            durationSeconds: 10,
            sourceWidth: 1920,
            sourceHeight: 1080,
            sourceFrameRate: 60,
            targetBytes: twentyMB
        )
        XCTAssertEqual(plan.width, 1920)
        XCTAssertEqual(plan.height, 1080)
        XCTAssertEqual(plan.frameRate, 60)
        XCTAssertTrue(plan.fitsTarget)
        XCTAssertLessThanOrEqual(plan.estimatedBytes, twentyMB)
        // ~14.3 Mbps available; the 0.20 bpp ceiling at 1080p60 is ~24.9 Mbps, so no cap applies.
        XCTAssertGreaterThan(plan.videoBitrate, 13_000_000)
    }

    func testLongClipStepsDownResolutionBeforeGivingUp() {
        // 2 minutes into 20 MB ≈ 1.2 Mbps total: 1080p60 is hopeless, 480p30 is fine.
        let plan = SizedExportPlanner.plan(
            durationSeconds: 120,
            sourceWidth: 1920,
            sourceHeight: 1080,
            sourceFrameRate: 60,
            targetBytes: twentyMB
        )
        XCTAssertLessThan(plan.height, 1080)
        XCTAssertEqual(plan.frameRate, 30)
        XCTAssertTrue(plan.fitsTarget)
        XCTAssertLessThanOrEqual(plan.estimatedBytes, twentyMB)
        XCTAssertGreaterThanOrEqual(
            Double(plan.videoBitrate) / Double(plan.width * plan.height * plan.frameRate),
            SizedExportPlanner.minimumBitsPerPixel
        )
    }

    func testHopelessBudgetStillReturnsSmallestRungAndFlagsIt() {
        // 30 minutes into 20 MB: nothing acceptable fits.
        let plan = SizedExportPlanner.plan(
            durationSeconds: 1800,
            sourceWidth: 1920,
            sourceHeight: 1080,
            sourceFrameRate: 60,
            targetBytes: twentyMB
        )
        XCTAssertEqual(plan.height, 360)
        XCTAssertEqual(plan.frameRate, 30)
        XCTAssertFalse(plan.fitsTarget)
        XCTAssertEqual(plan.videoBitrate, SizedExportPlanner.minimumVideoBitrate)
    }

    func testGenerousBudgetIsCappedByQualityCeiling() {
        let plan = SizedExportPlanner.plan(
            durationSeconds: 5,
            sourceWidth: 1280,
            sourceHeight: 720,
            sourceFrameRate: 30,
            targetBytes: 500_000_000
        )
        let ceiling = Int(SizedExportPlanner.maximumBitsPerPixel * 1280 * 720 * 30)
        XCTAssertEqual(plan.videoBitrate, ceiling)
        XCTAssertLessThan(plan.estimatedBytes, 10_000_000)
    }

    func testOutputDimensionsAreEvenAndKeepAspect() {
        // 13" MacBook Air panel: 2560×1664 (aspect 1.538…)
        let plan = SizedExportPlanner.plan(
            durationSeconds: 60,
            sourceWidth: 2560,
            sourceHeight: 1664,
            sourceFrameRate: 60,
            targetBytes: twentyMB
        )
        XCTAssertEqual(plan.width % 2, 0)
        XCTAssertEqual(plan.height % 2, 0)
        XCTAssertEqual(Double(plan.width) / Double(plan.height), 2560.0 / 1664.0, accuracy: 0.01)
    }

    func testNoAudioSpendsWholeBudgetOnVideo() {
        let withAudio = SizedExportPlanner.plan(
            durationSeconds: 30, sourceWidth: 1920, sourceHeight: 1080, sourceFrameRate: 60,
            targetBytes: twentyMB, hasAudio: true
        )
        let silent = SizedExportPlanner.plan(
            durationSeconds: 30, sourceWidth: 1920, sourceHeight: 1080, sourceFrameRate: 60,
            targetBytes: twentyMB, hasAudio: false
        )
        XCTAssertEqual(silent.audioBitrate, 0)
        XCTAssertEqual(silent.videoBitrate - withAudio.videoBitrate, withAudio.audioBitrate)
    }

    func testEstimateAndMaximumDurationAgree() {
        let bytes = SizedExportPlanner.estimatedBytes(videoBitrate: 4_000_000, audioBitrate: 128_000, durationSeconds: 30)
        XCTAssertEqual(bytes, Int64((4_128_000.0 * 30 / 8 * SizedExportPlanner.containerOverhead).rounded()))

        let seconds = SizedExportPlanner.maximumDuration(targetBytes: twentyMB, videoBitrate: 4_000_000, audioBitrate: 128_000)
        XCTAssertEqual(seconds, 20_000_000 * 8 * SizedExportPlanner.safetyFactor / 4_128_000, accuracy: 0.001)
    }

    func testDiscordPresetIsDecimalTwentyMegabytes() {
        XCTAssertEqual(SizedExportPlanner.Target.discordFree.bytes, 20_000_000)
        XCTAssertEqual(SizedExportPlanner.Target.presets.first, .discordFree)
    }
}
