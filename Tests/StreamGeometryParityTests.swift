import Foundation
import XCTest
@testable import BeetCode

/// Window-sizing and capture-resolution parity with the Sync/Stream hosts.
///
/// These cover the **pure** geometry only. The AX ordering fix (position before size) cannot be
/// asserted here: it needs a live window, a live display, and a real AX size set that AppKit
/// clamps — none of which a unit test has. It is verified live instead; see the report.
final class StreamGeometryParityTests: XCTestCase {

    @MainActor
    func testSizingRetryWaitsForTheAcceptedFrameBeforeReapplying() async throws {
        let requested = CGSize(width: 627, height: 1364)
        var observed = CGSize(width: 640, height: 480)
        var applications = 0
        var events: [String] = []
        let result = try await RemoteControlApplicationRegistry.applySettledFrame(
            requestedSize: requested, mode: .adaptive,
            apply: { applications += 1; events.append("apply"); return true },
            measure: { events.append("measure"); return observed },
            settle: {
                events.append("settle")
                observed = applications == 1 ? CGSize(width: 627, height: 900) : requested
            })
        XCTAssertEqual(events, ["apply", "settle", "measure", "apply", "settle", "measure"])
        XCTAssertTrue(result.retried)
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.observedSize, requested)
    }

    @MainActor
    func testAlreadyAcceptedResizeDoesNotRetryOnAStaleImmediateFrame() async throws {
        let requested = CGSize(width: 627, height: 1364)
        var observed = CGSize(width: 640, height: 480)
        var applications = 0
        let result = try await RemoteControlApplicationRegistry.applySettledFrame(
            requestedSize: requested, mode: .adaptive,
            apply: { applications += 1; return true },
            measure: { observed },
            settle: { observed = requested })
        XCTAssertEqual(applications, 1)
        XCTAssertFalse(result.retried)
        XCTAssertEqual(result.observedSize, requested)
    }

    @MainActor
    func testRejectedOrOriginalResizeNeverLoopsOnAppConstraints() async throws {
        let requested = CGSize(width: 627, height: 1364)
        for (mode, accepts): (RemoteControlApplicationRegistry.WindowSizingMode, Bool) in [(.adaptive, false), (.original, true)] {
            var applications = 0
            let result = try await RemoteControlApplicationRegistry.applySettledFrame(
                requestedSize: requested, mode: mode,
                apply: { applications += 1; return accepts },
                measure: { CGSize(width: 640, height: 480) },
                settle: {})
            XCTAssertEqual(applications, 1)
            XCTAssertFalse(result.retried)
        }
    }

    @MainActor
    func testSizingRequestSupportsLegacyAndMeasuredViewportWithoutInvertingPortrait() throws {
        let legacy = try RemoteControlApplicationRegistry.WindowSizingRequest(fields: [
            "windowID": .number(42), "clientViewportAspect": .number(0.5)])
        XCTAssertEqual(legacy.windowID, 42)
        XCTAssertNil(legacy.mode)
        XCTAssertNil(legacy.viewport)
        let modern = try RemoteControlApplicationRegistry.WindowSizingRequest(fields: [
            "windowID": .number(42), "clientViewportAspect": .number(0.5),
            "viewportWidth": .number(390), "viewportHeight": .number(794),
            "sizingMode": .string("adaptive")])
        XCTAssertEqual(modern.viewport, CGSize(width: 390, height: 794))
        XCTAssertEqual(modern.mode, .adaptive)
    }

    @MainActor
    func testSizingRequestRejectsPartialInvalidOrUnknownSizingFields() {
        let valid: [String: LFJSONValue] = ["windowID": .number(42), "clientViewportAspect": .number(0.5)]
        for invalid: [String: LFJSONValue] in [
            ["windowID": .number(42.5)], ["windowID": .number(0)],
            ["windowID": .number(Double(UInt32.max) + 1)],
            ["clientViewportAspect": .number(.nan)], ["clientViewportAspect": .number(5)],
            ["viewportWidth": .number(390)],
            ["viewportWidth": .number(390), "viewportHeight": .number(0)],
            ["viewportWidth": .number(.infinity), "viewportHeight": .number(794)],
            ["sizingMode": .string("unknown")]
        ] {
            XCTAssertThrowsError(try RemoteControlApplicationRegistry.WindowSizingRequest(
                fields: valid.merging(invalid) { _, new in new }))
        }
    }

    @MainActor
    func testOriginalSizeSurvivesMultipleAdaptiveRequestsAndWindowIDReuse() {
        typealias Key = RemoteControlApplicationRegistry.OriginalWindowSizes.Key
        var originals = RemoteControlApplicationRegistry.OriginalWindowSizes()
        let key = Key(windowID: 42, pid: 100)
        let original = CGSize(width: 1100, height: 700)
        XCTAssertEqual(originals.remember(original, for: key, liveKeys: [key]), original)
        XCTAssertEqual(originals.remember(CGSize(width: 627, height: 1364), for: key, liveKeys: [key]), original)
        let reused = Key(windowID: 42, pid: 200)
        let newSize = CGSize(width: 800, height: 600)
        XCTAssertEqual(originals.remember(newSize, for: reused, liveKeys: [reused]), newSize)
        XCTAssertNil(originals.sizes[key])
    }

    @MainActor
    func testOriginalWindowSizeRetentionIsBounded() {
        typealias Key = RemoteControlApplicationRegistry.OriginalWindowSizes.Key
        var originals = RemoteControlApplicationRegistry.OriginalWindowSizes()
        let keys = (1...200).map { Key(windowID: UInt32($0), pid: 100) }
        for key in keys {
            _ = originals.remember(CGSize(width: 800, height: 600), for: key, liveKeys: Set(keys))
            XCTAssertLessThanOrEqual(originals.sizes.count, 128)
        }
    }

    func testOriginalRestoresExactDimensionsWithoutApplyingViewportAspect() {
        let frame = RemoteControlApplicationRegistry.targetWindowFrame(
            current: CGRect(x: 1800, y: 900, width: 627, height: 1364),
            display: CGRect(x: 0, y: 0, width: 2560, height: 1440), aspect: 390.0 / 794.0,
            originalSize: CGSize(width: 1100, height: 700), sizingMode: .original)
        XCTAssertEqual(frame.size, CGSize(width: 1100, height: 700))
        XCTAssertLessThanOrEqual(frame.maxX, 2536)
        XCTAssertLessThanOrEqual(frame.maxY, 1416)
    }

    func testOriginalSizeIsConstrainedToTheWindowsActualDisplay() {
        let frame = RemoteControlApplicationRegistry.targetWindowFrame(
            current: CGRect(x: -500, y: 900, width: 627, height: 1364),
            display: CGRect(x: -1920, y: 0, width: 1920, height: 1080), aspect: 0.5,
            originalSize: CGSize(width: 2560, height: 1440), sizingMode: .original)
        XCTAssertEqual(frame.size, CGSize(width: 1872, height: 1004))
        XCTAssertEqual(frame.origin, CGPoint(x: -1896, y: 52))
    }

    private let maxLongEdge = 3840
    private let maxPixels = 3840 * 2160

    private func fit(_ width: Int, _ height: Int) -> (width: Int, height: Int) {
        RemoteMacScreenCapture.fittedPixelSize(
            pixelWidth: width,
            pixelHeight: height,
            maxLongEdge: maxLongEdge,
            maxPixels: maxPixels)
    }

    // MARK: Capture ceilings

    func testNearSquareWindowIsBoundedByTotalPixelsNotJustLongEdge() {
        // 3800x3800 is 14.4 MP and passes a 3840 long-edge cap untouched. Only the
        // pixel ceiling catches it.
        let source = (width: 3800, height: 3800)
        let fitted = fit(source.width, source.height)

        XCTAssertLessThanOrEqual(
            fitted.width * fitted.height, maxPixels,
            "a near-square window must stay inside the 4K UHD pixel envelope")
        XCTAssertLessThanOrEqual(max(fitted.width, fitted.height), maxLongEdge)
        XCTAssertLessThan(fitted.width * fitted.height, source.width * source.height)
        // Aspect preserved within a pixel of even-rounding.
        XCTAssertEqual(Double(fitted.width) / Double(fitted.height),
                       Double(source.width) / Double(source.height),
                       accuracy: 0.01)
        XCTAssertEqual(fitted.width % 2, 0)
        XCTAssertEqual(fitted.height % 2, 0)
    }

    func testPortraitWindowAlreadyInsideBothCeilingsPassesThroughUntouched() {
        // The case that produced the soft picture: a 2560x1440 Mac fitted to a portrait
        // phone yields 1334x2728. Both ceilings allow it, so it must NOT be rescaled —
        // 1334 * 2728 = 3.64 MP, well inside 8.29 MP, and 2728 < 3840.
        let fitted = fit(1334, 2728)

        XCTAssertEqual(fitted.width, 1334)
        XCTAssertEqual(fitted.height, 2728)
    }

    func testFourKUHDIsExactlyAtBothCeilingsAndIsNotRescaled() {
        let fitted = fit(3840, 2160)

        XCTAssertEqual(fitted.width, 3840)
        XCTAssertEqual(fitted.height, 2160)
    }

    func testLandscapeSourcesScaleExactlyAsBefore() {
        // Regression guard on the previous behaviour: a whole 5K display capped to 3840
        // must still scale by long edge alone.
        let fitted = fit(5120, 2880)

        XCTAssertEqual(max(fitted.width, fitted.height), maxLongEdge)
        XCTAssertEqual(Double(fitted.width) / Double(fitted.height),
                       Double(5120) / Double(2880),
                       accuracy: 0.01)
    }

    func testCeilingsNeverUpscaleASmallerSource() {
        let fitted = fit(800, 600)

        XCTAssertEqual(fitted.width, 800)
        XCTAssertEqual(fitted.height, 600)
    }

    func testOddSourceDimensionsAreRoundedEvenWithoutGrowth() {
        let fitted = fit(1335, 2729)

        XCTAssertEqual(fitted.width % 2, 0)
        XCTAssertEqual(fitted.height % 2, 0)
        XCTAssertLessThanOrEqual(fitted.width, 1335)
        XCTAssertLessThanOrEqual(fitted.height, 2729)
    }

    func testNilCeilingsLeaveTheSourceOnlyEvenedForH264() {
        let fitted = RemoteMacScreenCapture.fittedPixelSize(
            pixelWidth: 4001,
            pixelHeight: 3001,
            maxLongEdge: nil,
            maxPixels: nil)

        XCTAssertEqual(fitted.width, 4000)
        XCTAssertEqual(fitted.height, 3000)
    }

    func testDegenerateSourceStillProducesAnEncodableSize() {
        let fitted = fit(1, 1)

        XCTAssertGreaterThanOrEqual(fitted.width, 2)
        XCTAssertGreaterThanOrEqual(fitted.height, 2)
        XCTAssertEqual(fitted.width % 2, 0)
        XCTAssertEqual(fitted.height % 2, 0)
    }

    // MARK: Anchor / ordering support

    func testAnchorKeepsOriginWhenTheRequestedSizeStillFits() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // Usable height is 1080 - 76 = 1004, so a 400pt-tall window has room for
        // any origin from 52 up to 52 + (1004 - 400) = 656.
        let origin = RemoteControlApplicationRegistry.anchoredOrigin(
            requestedSize: CGSize(width: 600, height: 400),
            currentOrigin: CGPoint(x: 300, y: 200),
            display: display)

        XCTAssertEqual(origin.x, 300)
        XCTAssertEqual(origin.y, 200)
    }

    func testAnchorRaisesAWindowThatCannotFitBelowItsOrigin() {
        // A 900pt-tall window low on a 1080pt display: the origin is raised to the
        // highest position the usable area allows, rather than letting AppKit clamp
        // the height to the room below the old origin.
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = RemoteControlApplicationRegistry.anchoredOrigin(
            requestedSize: CGSize(width: 600, height: 900),
            currentOrigin: CGPoint(x: 300, y: 200),
            display: display)

        XCTAssertEqual(origin.x, 300, "x already fitted")
        XCTAssertEqual(origin.y, 156, "52 + (1004 - 900) is the highest fitting origin")
        XCTAssertEqual(origin.y + 900, 1080 - 24, "lands exactly on the bottom margin")
    }

    func testAnchorPushesALowWindowUpSoTheRequestedHeightFits() {
        // The exact shape of the bug: a window near the bottom of the display. The old order
        // sized first, so AppKit clamped the height to the room below the OLD origin. The
        // anchor is computed from the REQUESTED size, so there is room for it after the move.
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let requested = CGSize(width: 500, height: 900)
        let origin = RemoteControlApplicationRegistry.anchoredOrigin(
            requestedSize: requested,
            currentOrigin: CGPoint(x: 400, y: 900),
            display: display)

        // usable area is inset 24 left/right and 52 top with a 24 bottom margin (1080-76).
        XCTAssertLessThanOrEqual(origin.y + requested.height, 1080 - 24)
        XCTAssertGreaterThanOrEqual(origin.y, 52)
        XCTAssertEqual(origin.y, 156, "pushed up to fit the requested height")
        XCTAssertEqual(origin.x, 400, "x already fitted")
    }

    func testAnchorHonoursTheTopInsetAndRightEdge() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let requested = CGSize(width: 800, height: 600)
        let origin = RemoteControlApplicationRegistry.anchoredOrigin(
            requestedSize: requested,
            currentOrigin: CGPoint(x: 1900, y: -400),
            display: display)

        XCTAssertGreaterThanOrEqual(origin.x, 24)
        XCTAssertLessThanOrEqual(origin.x + requested.width, 1920 - 24)
        XCTAssertGreaterThanOrEqual(origin.y, 52)
    }

    func testAnchorOffsetsWithATranslatedDisplay() {
        let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let origin = RemoteControlApplicationRegistry.anchoredOrigin(
            requestedSize: CGSize(width: 400, height: 400),
            currentOrigin: CGPoint(x: -1800, y: 100),
            display: display)

        XCTAssertGreaterThanOrEqual(origin.x, -1920 + 24)
        XCTAssertLessThanOrEqual(origin.x + 400, 0 - 24)
    }

    // MARK: Window fitting (Sync `AdaptiveWindowSizing` parity)

    func testFitExpandsASmallSourceWindowInsteadOfShrinkingIt() {
        // Terminal's default is about 528x374. Shrink-only turned a portrait request into
        // roughly 172x374, which the phone upscaled ~3x. The fit must instead grow the matched
        // shape to fill the display.
        let frame = RemoteControlApplicationRegistry.targetWindowFrame(
            current: CGRect(x: 100, y: 100, width: 528, height: 374),
            display: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            aspect: 9.0 / 19.5)

        XCTAssertEqual(frame.width / frame.height, 9.0 / 19.5, accuracy: 0.003)
        XCTAssertGreaterThan(frame.height, 374, "must expand, not shrink to the source")
        XCTAssertGreaterThan(frame.width, 172, "the old shrink-only width")
    }

    func testFitCapsTheLongestEdgeForLargeDisplays() {
        // A 5K-class display would otherwise yield a portrait window taller than the client's
        // hardware decoder accepts.
        let frame = RemoteControlApplicationRegistry.targetWindowFrame(
            current: CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
            display: CGRect(x: 0, y: 0, width: 5_120, height: 2_880),
            aspect: 9.0 / 19.5)

        XCTAssertLessThanOrEqual(
            max(frame.width, frame.height),
            RemoteControlApplicationRegistry.maxEdgePoints,
            "longest edge must respect the decoder envelope")
        XCTAssertEqual(frame.width / frame.height, 9.0 / 19.5, accuracy: 0.003)
    }

    func testFitStaysInsideTheUsableDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let frame = RemoteControlApplicationRegistry.targetWindowFrame(
            current: CGRect(x: 1_500, y: 900, width: 1_280, height: 800),
            display: display,
            aspect: 9.0 / 19.5)

        XCTAssertGreaterThanOrEqual(frame.minX, 24)
        XCTAssertGreaterThanOrEqual(frame.minY, 52)
        XCTAssertLessThanOrEqual(frame.maxX, 1_896)
        XCTAssertLessThanOrEqual(frame.maxY, 1_056)
    }

    func testFitClampsAnOutOfRangeAspect() {
        // The viewport aspect is clamped to 0.25...4 before matching, as the Sync host does.
        let frame = RemoteControlApplicationRegistry.targetWindowFrame(
            current: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            display: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            aspect: 99)

        XCTAssertEqual(frame.width / frame.height, 4, accuracy: 0.01)
    }

    func testFitLeavesANonPositiveAspectAlone() {
        let current = CGRect(x: 10, y: 10, width: 500, height: 400)

        XCTAssertEqual(RemoteControlApplicationRegistry.targetWindowFrame(
            current: current, display: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            aspect: 0), current)
    }

    // MARK: Aspect mismatch predicate

    func testAspectMismatchDetectsALetterboxedShape() {
        // Safari's real behaviour: asked for 221x480 (0.4604), accepted 574x480 (1.1958).
        XCTAssertTrue(RemoteControlApplicationRegistry.aspectMismatch(
            CGSize(width: 574, height: 480),
            desired: CGSize(width: 221, height: 480)))
    }

    func testAspectMismatchToleratesASmallSizeDifference() {
        // 3pt off the request is fine — shape is what the phone renders.
        XCTAssertFalse(RemoteControlApplicationRegistry.aspectMismatch(
            CGSize(width: 221, height: 483),
            desired: CGSize(width: 221, height: 480)))
    }

    func testAspectMismatchToleranceBoundary() {
        // Identical shapes never mismatch.
        XCTAssertFalse(RemoteControlApplicationRegistry.aspectMismatch(
            CGSize(width: 100, height: 200), desired: CGSize(width: 100, height: 200)))
        // 100/200 = 0.500 vs 100/190 = 0.526: a 0.026 gap, inside the 0.05 tolerance.
        XCTAssertFalse(RemoteControlApplicationRegistry.aspectMismatch(
            CGSize(width: 100, height: 190), desired: CGSize(width: 100, height: 200)))
        // 100/200 = 0.500 vs 100/120 = 0.833: a 0.333 gap, outside it.
        XCTAssertTrue(RemoteControlApplicationRegistry.aspectMismatch(
            CGSize(width: 100, height: 120), desired: CGSize(width: 100, height: 200)))
    }

    func testAspectMismatchRejectsDegenerateInput() {
        XCTAssertFalse(RemoteControlApplicationRegistry.aspectMismatch(
            CGSize(width: 0, height: 100), desired: CGSize(width: 100, height: 200)))
        XCTAssertFalse(RemoteControlApplicationRegistry.aspectMismatch(
            CGSize(width: 100, height: 200), desired: CGSize(width: 0, height: 0)))
    }

    // MARK: AX window matching

    func testUniqueWindowMatchRequiresOneCandidate() {
        let target = CGRect(x: 100, y: 100, width: 800, height: 600)
        let other = CGRect(x: 400, y: 300, width: 500, height: 400)

        XCTAssertEqual(
            RemoteControlApplicationRegistry.uniqueWindowIndex(
                matching: target, among: [other, target, other]), 1)
    }

    func testAmbiguousOriginAndSizeIsRefusedRatherThanGuessed() {
        // Two windows of the same app at the same frame: matching either would be a guess,
        // and reshaping the wrong one is invisible until the phone shows the wrong window.
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

        XCTAssertNil(RemoteControlApplicationRegistry.uniqueWindowIndex(
            matching: frame, among: [frame, frame]))
    }

    func testNoCandidateIsRefused() {
        XCTAssertNil(RemoteControlApplicationRegistry.uniqueWindowIndex(
            matching: CGRect(x: 10, y: 10, width: 100, height: 100),
            among: []))
        XCTAssertNil(RemoteControlApplicationRegistry.uniqueWindowIndex(
            matching: CGRect(x: 10, y: 10, width: 100, height: 100),
            among: [CGRect(x: 500, y: 500, width: 100, height: 100)]))
    }

    func testSameOriginButDifferentSizeIsRefused() {
        // Origin-only matching used to accept this and reshape the wrong window.
        let target = CGRect(x: 100, y: 100, width: 800, height: 600)
        let resized = CGRect(x: 100, y: 100, width: 640, height: 480)

        XCTAssertNil(RemoteControlApplicationRegistry.uniqueWindowIndex(
            matching: target, among: [resized]))
    }

    func testMatchToleratesTwoPointsOnOriginAndSize() {
        let target = CGRect(x: 100, y: 100, width: 800, height: 600)
        let nearly = CGRect(x: 102, y: 98, width: 802, height: 598)

        XCTAssertEqual(
            RemoteControlApplicationRegistry.uniqueWindowIndex(
                matching: target, among: [nearly]), 0)
    }
}
