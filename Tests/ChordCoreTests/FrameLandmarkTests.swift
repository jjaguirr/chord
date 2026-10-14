import Testing
@testable import ChordCore

/// Checks the generated landmarks in FrameLandmarkFixtures.swift. Each entry
/// was found by bisecting frame() itself (scripts/generate-frame-fixtures.sh).
@Suite("frame() landmarks")
struct FrameLandmarkTests {
    @Test func fixturesCoverFiveResolutionsByFourTargets() {
        #expect(frameLandmarks.count == 20)
    }

    @Test func frameAtEachLandmarkMatchesFixtureWithinOnePixel() {
        for landmark in frameLandmarks {
            let f = frame(landmark.t, screenW: landmark.screenW, screenH: landmark.screenH)
            let context = "\(landmark.screenW)x\(landmark.screenH) \(landmark.name)"
            #expect(abs(f.w - landmark.w) <= 1, Comment(rawValue: context))
            #expect(abs(f.h - landmark.h) <= 1, Comment(rawValue: context))
        }
    }

    @Test func frameAtEachLandmarkHasTargetRatio() {
        // Confirms each t is a real ratio crossing, not a stale or drifted value.
        for landmark in frameLandmarks {
            let f = frame(landmark.t, screenW: landmark.screenW, screenH: landmark.screenH)
            let context = "\(landmark.screenW)x\(landmark.screenH) \(landmark.name)"
            #expect(abs(f.ratio - landmark.ratio) < 1e-9, Comment(rawValue: context))
        }
    }

    @Test func landmarkTIsIdenticalAcrossResolutions() {
        // S2 is always 16:9, so the crossing does not depend on the screen.
        for name in ["square", "fourByThree", "threeByTwo", "goldenRectangle"] {
            let ts = frameLandmarks.filter { $0.name == name }.map(\.t)
            #expect(ts.count == 5, Comment(rawValue: name))
            for t in ts {
                #expect(abs(t - ts[0]) < 1e-9, Comment(rawValue: name))
            }
        }
    }

    @Test func landmarksRiseWithTargetRatioAtEachResolution() {
        // Within each resolution, the crossing t rises with the target ratio.
        let resolutions = Set(frameLandmarks.map { "\($0.screenW)x\($0.screenH)" })
        for resolution in resolutions {
            let ts = frameLandmarks
                .filter { "\($0.screenW)x\($0.screenH)" == resolution }
                .sorted { $0.ratio < $1.ratio }
                .map(\.t)
            #expect(ts == ts.sorted(), Comment(rawValue: resolution))
        }
    }
}
