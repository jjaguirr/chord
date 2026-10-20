import Testing
@testable import ChordCore

@Suite("AeroSpaceHealth")
struct AeroSpaceHealthTests {
    private let pin = "v0.21.3-Beta"
    private let pinnedServer = "0.21.3-Beta 0123abcd"
    private let oldServer = "0.20.3-Beta 6dde91ba43f6"

    private func health(_ probe: AeroSpaceProbe) -> AeroSpaceHealth {
        AeroSpaceHealth(probe: probe, pinnedTag: pin)
    }

    @Test func versionMatchesOnlyTheExactPinnedRelease() {
        #expect(AeroSpaceVersion.matches(pinnedTag: pin, serverVersionAndHash: pinnedServer))
        #expect(AeroSpaceVersion.matches(pinnedTag: "0.21.3-Beta", serverVersionAndHash: pinnedServer))
        #expect(!AeroSpaceVersion.matches(pinnedTag: pin, serverVersionAndHash: oldServer))
        #expect(!AeroSpaceVersion.matches(pinnedTag: pin, serverVersionAndHash: "0.21.30-Beta abc"))
        #expect(!AeroSpaceVersion.matches(pinnedTag: pin, serverVersionAndHash: ""))
        #expect(!AeroSpaceVersion.matches(pinnedTag: "", serverVersionAndHash: ""))
        #expect(!AeroSpaceVersion.matches(pinnedTag: "v", serverVersionAndHash: ""))
    }

    @Test func aServerThatRanTheQueryAtThePinnedVersionIsReadyWithNoNextStep() {
        let result = health(.answered(serverVersion: pinnedServer))
        #expect(result.isReady)
        #expect(result.nextStep == nil)
        #expect(result.report == result.summary)
    }

    @Test func aMissingSocketAndAStaleSocketAreBothNotRunning() {
        for probe in [AeroSpaceProbe.socketMissing, .refused("Connection refused")] {
            let result = health(probe)
            #expect(result.status == .notRunning)
            #expect(!result.isReady)
            #expect(result.nextStep?.contains("Install AeroSpace v0.21.3-Beta") == true)
        }
    }

    @Test func aDisabledServerShowsTheCommandAndNeverIsReady() {
        let result = health(.serverDisabled(serverVersion: pinnedServer))
        #expect(result.status == .disabled)
        #expect(!result.isReady)
        let step = result.nextStep ?? ""
        #expect(step.contains("Chord never turns it on"))
        #expect(step.contains("aerospace enable on"))
        #expect(result.report.hasPrefix(result.summary))
    }

    @Test func aWrongVersionIsReportedBeforeADisabledServer() {
        #expect(health(.serverDisabled(serverVersion: oldServer)).status == .wrongVersion(found: oldServer))
        #expect(health(.answered(serverVersion: oldServer)).status == .wrongVersion(found: oldServer))
        #expect(health(.rejected(serverVersion: oldServer, message: "x")).status == .wrongVersion(found: oldServer))
        #expect(health(.answered(serverVersion: oldServer)).summary.contains("0.20.3-Beta"))
        #expect(health(.answered(serverVersion: oldServer)).summary.contains(pin))
    }

    @Test func everyUnhealthyVerdictCarriesANextStep() {
        let probes: [AeroSpaceProbe] = [
            .socketMissing, .refused("r"), .protocolMismatch, .unreachable("timed out"),
            .serverDisabled(serverVersion: pinnedServer), .answered(serverVersion: oldServer),
            .rejected(serverVersion: pinnedServer, message: "boom"),
        ]
        for probe in probes {
            let result = health(probe)
            #expect(!result.isReady)
            #expect(result.nextStep?.isEmpty == false, "\(probe) needs a next step")
        }
    }

    @Test func aProtocolMismatchNamesTheFramingChange() {
        let result = health(.protocolMismatch)
        #expect(result.status == .protocolMismatch)
        #expect(result.nextStep?.contains("before 0.21") == true)
    }
}
