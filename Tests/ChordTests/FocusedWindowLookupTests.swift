import ApplicationServices
import Testing
@testable import Chord

private final class FakeTree: AXTree {
    var focused: Result<Int, AXFailure> = .success(1)
    var attributes: [String: Result<Int, AXFailure>] = [:]
    var chromium = true
    var manualStatus: AXError = .success
    /// The focused-window read number (counted from 1, across the tree's life) from which it succeeds.
    var focusedWindowAppearsAtRead: Int?
    private(set) var focusedReads = 0
    private(set) var manualSets = 0

    func focusedApplication() -> Result<Int, AXFailure> { focused }
    func element(of parent: Int, attribute: String) -> Result<Int, AXFailure> {
        if attribute == kAXFocusedWindowAttribute {
            focusedReads += 1
            if let appears = focusedWindowAppearsAtRead, focusedReads >= appears, manualSets > 0 { return .success(8) }
        }
        return attributes[attribute] ?? .failure(AXFailure(code: .noValue))
    }
    func isChromiumBased(_ app: Int) -> Bool { chromium }
    func setBool(_ attribute: String, on app: Int) -> AXError {
        #expect(attribute == "AXManualAccessibility")
        manualSets += 1
        return manualStatus
    }
}

@Suite("Focused window lookup")
struct FocusedWindowLookupTests {
    private func lookup(_ tree: FakeTree, sleeps: SleepLog = SleepLog()) -> FocusedWindowLookup<FakeTree> {
        FocusedWindowLookup(tree: tree, appKey: { $0 }, sleep: { sleeps.intervals.append($0) })
    }

    private final class SleepLog {
        var intervals: [Double] = []
    }

    @Test func focusedWindowWinsWithoutTouchingTheApp() {
        let tree = FakeTree()
        tree.attributes[kAXFocusedWindowAttribute] = .success(7)
        guard case .found(let window, let via) = lookup(tree).find() else {
            Issue.record("expected found")
            return
        }
        #expect(window == 7)
        #expect(via == "focused window")
        #expect(tree.manualSets == 0)
    }

    @Test func chromiumAnswersFocusedWindowOnlyAfterManualAccessibility() {
        let tree = FakeTree()
        tree.focusedWindowAppearsAtRead = 2
        let sleeps = SleepLog()
        guard case .found(let window, let via) = lookup(tree, sleeps: sleeps).find() else {
            Issue.record("expected found")
            return
        }
        #expect(window == 8)
        #expect(via.contains("AXManualAccessibility"))
        #expect(sleeps.intervals == [0.05])
    }

    @Test func chromeTreeTakingLongerThanTheFormerRetryWindowStillFindsItsFocusedWindow() {
        let tree = FakeTree()
        tree.focusedWindowAppearsAtRead = 7
        let sleeps = SleepLog()

        guard case .found(let window, let via) = lookup(tree, sleeps: sleeps).find() else {
            Issue.record("expected Chromium's delayed focused window")
            return
        }

        #expect(window == 8)
        #expect(via.contains("AXManualAccessibility"))
        #expect(sleeps.intervals == Array(repeating: 0.05, count: 6))
    }

    @Test func retriesAreBoundedAndSpacedWhenTheTreeNeverAppears() {
        let tree = FakeTree()
        let sleeps = SleepLog()
        guard case .notFound(let reason) = lookup(tree, sleeps: sleeps).find() else {
            Issue.record("expected notFound")
            return
        }
        #expect(tree.focusedReads == 11)
        #expect(sleeps.intervals == Array(repeating: 0.05, count: 10))
        #expect(reason.contains("AXManualAccessibility set ok"))
        #expect(reason.contains("focused retry 10 noValue(-25212)"))
    }

    @Test func manualAccessibilityIsSetOncePerApp() {
        let tree = FakeTree()
        let finder = lookup(tree)
        _ = finder.find()
        _ = finder.find()
        #expect(tree.manualSets == 1)
    }

    @Test func failedSetIsRetriedOnTheNextLookupWithoutReadRetries() {
        let tree = FakeTree()
        tree.manualStatus = .cannotComplete
        let sleeps = SleepLog()
        let finder = lookup(tree, sleeps: sleeps)
        guard case .notFound(let reason) = finder.find() else {
            Issue.record("expected notFound")
            return
        }
        _ = finder.find()
        #expect(tree.manualSets == 2)
        #expect(sleeps.intervals.isEmpty)
        #expect(reason.contains("AXManualAccessibility set cannotComplete(-25204)"))
    }

    @Test func nonChromiumAppsAreNeverTouched() {
        let tree = FakeTree()
        tree.chromium = false
        tree.attributes[kAXMainWindowAttribute] = .success(9)
        guard case .notFound(let reason) = lookup(tree).find() else {
            Issue.record("expected notFound")
            return
        }
        #expect(tree.manualSets == 0)
        #expect(reason == "focused noValue(-25212)")
    }

    @Test func failureReportsTheFocusedReadsErrorCode() {
        let tree = FakeTree()
        tree.chromium = false
        tree.attributes[kAXFocusedWindowAttribute] = .failure(AXFailure(code: .cannotComplete))
        guard case .notFound(let reason) = lookup(tree).find() else {
            Issue.record("expected notFound")
            return
        }
        #expect(reason == "focused cannotComplete(-25204)")
    }

    @Test func noFocusedApplicationIsReported() {
        let tree = FakeTree()
        tree.focused = .failure(AXFailure(code: .noValue))
        guard case .notFound(let reason) = lookup(tree).find() else {
            Issue.record("expected notFound")
            return
        }
        #expect(reason.contains("focused application"))
    }
}

@Suite("Chromium detection")
struct ChromiumDetectionTests {
    @Test func knownBrowserBundleIDsMatch() {
        for id in ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
                   "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.brave.Browser", "com.brave.Browser.nightly",
                   "company.thebrowser.Browser", "org.chromium.Chromium", "com.vivaldi.Vivaldi",
                   "com.vivaldi.Vivaldi.snapshot", "com.operasoftware.Opera", "com.operasoftware.OperaGX",
                   "com.operasoftware.OperaNext"] {
            #expect(LiveAXTree.isChromiumBased(bundleID: id, bundleURL: nil), "\(id)")
        }
        #expect(!LiveAXTree.isChromiumBased(bundleID: "com.apple.finder", bundleURL: nil))
        #expect(!LiveAXTree.isChromiumBased(bundleID: nil, bundleURL: nil))
    }

    @Test func bundlesEmbeddingElectronOrCEFMatch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(_ name: String, framework: String?) throws -> URL {
            let url = root.appendingPathComponent(name)
            let frameworks = url.appendingPathComponent("Contents/Frameworks")
            try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
            if let framework {
                try FileManager.default.createDirectory(
                    at: frameworks.appendingPathComponent(framework), withIntermediateDirectories: true)
            }
            return url
        }
        let electron = try bundle("E.app", framework: "Electron Framework.framework")
        let cef = try bundle("C.app", framework: "Chromium Embedded Framework.framework")
        let native = try bundle("N.app", framework: "Sparkle.framework")
        #expect(LiveAXTree.isChromiumBased(bundleID: "com.example.e", bundleURL: electron))
        #expect(LiveAXTree.isChromiumBased(bundleID: "com.example.c", bundleURL: cef))
        #expect(!LiveAXTree.isChromiumBased(bundleID: "com.example.n", bundleURL: native))
    }
}
