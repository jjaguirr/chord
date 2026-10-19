import ApplicationServices
import Testing
@testable import Chord

private final class FakeTree: AXTree {
    var focused: Result<Int, AXFailure> = .success(1)
    var attributes: [String: Result<Int, AXFailure>] = [:]
    var windowList: Result<[Int], AXFailure> = .success([])
    var subroles: [Int: String] = [:]
    /// Attribute values that appear once AXManualAccessibility has been set.
    var afterManual: [String: Result<Int, AXFailure>] = [:]
    var manualStatus: AXError = .success
    private(set) var manualSets = 0

    func focusedApplication() -> Result<Int, AXFailure> { focused }
    func element(of parent: Int, attribute: String) -> Result<Int, AXFailure> {
        if manualSets > 0, let value = afterManual[attribute] { return value }
        return attributes[attribute] ?? .failure(AXFailure(code: .noValue))
    }
    func windows(of app: Int) -> Result<[Int], AXFailure> { windowList }
    func subrole(of window: Int) -> String? { subroles[window] }
    func setBool(_ attribute: String, on app: Int) -> AXError {
        #expect(attribute == "AXManualAccessibility")
        manualSets += 1
        return manualStatus
    }
}

@Suite("Focused window lookup")
struct FocusedWindowLookupTests {
    private func via(_ result: FocusedWindowLookupResult<Int>) -> (Int, String)? {
        if case .found(let window, let via) = result { return (window, via) }
        return nil
    }

    @Test func focusedWindowWinsWithoutTouchingTheApp() {
        let tree = FakeTree()
        tree.attributes[kAXFocusedWindowAttribute] = .success(7)
        let lookup = FocusedWindowLookup(tree: tree) { $0 }
        #expect(via(lookup.find())?.0 == 7)
        #expect(tree.manualSets == 0)
    }

    @Test func chromiumAnswersFocusedWindowOnlyAfterManualAccessibility() {
        let tree = FakeTree()
        tree.afterManual[kAXFocusedWindowAttribute] = .success(8)
        let lookup = FocusedWindowLookup(tree: tree) { $0 }
        let found = via(lookup.find())
        #expect(found?.0 == 8)
        #expect(found?.1.contains("AXManualAccessibility") == true)
    }

    @Test func manualAccessibilityIsSetOncePerApp() {
        let tree = FakeTree()
        let lookup = FocusedWindowLookup(tree: tree) { $0 }
        _ = lookup.find()
        _ = lookup.find()
        #expect(tree.manualSets == 1)
    }

    @Test func fallsBackToMainWindow() {
        let tree = FakeTree()
        tree.attributes[kAXMainWindowAttribute] = .success(9)
        let lookup = FocusedWindowLookup(tree: tree) { $0 }
        #expect(via(lookup.find())?.1 == "main window")
    }

    @Test func fallsBackToFirstStandardWindowSkippingPanels() {
        let tree = FakeTree()
        tree.windowList = .success([3, 4, 5])
        tree.subroles = [3: "AXFloatingWindow", 4: kAXStandardWindowSubrole as String, 5: kAXStandardWindowSubrole as String]
        let lookup = FocusedWindowLookup(tree: tree) { $0 }
        let found = via(lookup.find())
        #expect(found?.0 == 4)
        #expect(found?.1 == "first standard window")
    }

    @Test func failureReportsEachAttributesErrorCode() {
        let tree = FakeTree()
        tree.attributes[kAXFocusedWindowAttribute] = .failure(AXFailure(code: .cannotComplete))
        tree.attributes[kAXMainWindowAttribute] = .failure(AXFailure(code: .attributeUnsupported))
        tree.windowList = .failure(AXFailure(code: .apiDisabled))
        let lookup = FocusedWindowLookup(tree: tree) { $0 }
        guard case .notFound(let reason) = lookup.find() else {
            Issue.record("expected notFound")
            return
        }
        #expect(reason.contains("focused cannotComplete(-25204)"))
        #expect(reason.contains("main attributeUnsupported(-25205)"))
        #expect(reason.contains("windows apiDisabled(-25211)"))
    }

    @Test func noFocusedApplicationIsReported() {
        let tree = FakeTree()
        tree.focused = .failure(AXFailure(code: .noValue))
        let lookup = FocusedWindowLookup(tree: tree) { $0 }
        guard case .notFound(let reason) = lookup.find() else {
            Issue.record("expected notFound")
            return
        }
        #expect(reason.contains("focused application"))
    }
}
