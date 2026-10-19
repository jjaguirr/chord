import Foundation
import ApplicationServices

/// The Accessibility reads and the one write the focused-window lookup needs, behind a
/// protocol so the lookup order is testable with a fake.
protocol AXTree {
    associatedtype Element

    /// The system-wide focused application.
    func focusedApplication() -> Result<Element, AXFailure>
    /// An element-valued attribute, such as `kAXFocusedWindowAttribute`.
    func element(of parent: Element, attribute: String) -> Result<Element, AXFailure>
    /// Whether the application is Chromium-based or Electron, the only kinds that need
    /// `AXManualAccessibility` before they answer.
    func isChromiumBased(_ app: Element) -> Bool
    /// Sets a boolean attribute on the application element.
    func setBool(_ attribute: String, on app: Element) -> AXError
}

/// Where a window was found, or why it was not.
enum FocusedWindowLookupResult<Element> {
    case found(Element, via: String)
    case notFound(reason: String)
}

/// Finds the focused window of the focused application.
///
/// Chromium (Chrome, Edge, Brave, Arc, Electron) builds its accessibility tree lazily and
/// answers a plain AX client's `kAXFocusedWindow` with an error until told an assistive
/// client is present. Order: focused window; then, for Chromium-based apps only, set
/// `AXManualAccessibility` (the documented Chromium/Electron switch, no animation cost,
/// unlike `AXEnhancedUserInterface`) and re-read the focused window a bounded number of
/// times while the tree is built. The app is latched only once the set succeeds.
final class FocusedWindowLookup<Tree: AXTree> {
    static var retryAttempts: Int { 3 }
    static var retryInterval: Double { 0.05 }

    private let tree: Tree
    private let appKey: (Tree.Element) -> Int
    private let sleep: (Double) -> Void
    private var enabledApps: Set<Int> = []

    init(
        tree: Tree,
        appKey: @escaping (Tree.Element) -> Int,
        sleep: @escaping (Double) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.tree = tree
        self.appKey = appKey
        self.sleep = sleep
    }

    func find() -> FocusedWindowLookupResult<Tree.Element> {
        let app: Tree.Element
        switch tree.focusedApplication() {
        case .success(let value): app = value
        case .failure(let error): return .notFound(reason: "focused application: \(Self.name(error.code))")
        }

        var failures: [String] = []
        func attempt(_ attribute: String, label: String) -> Tree.Element? {
            switch tree.element(of: app, attribute: attribute) {
            case .success(let window): return window
            case .failure(let error):
                failures.append("\(label) \(Self.name(error.code))")
                return nil
            }
        }

        if let window = attempt(kAXFocusedWindowAttribute, label: "focused") {
            return .found(window, via: "focused window")
        }

        if tree.isChromiumBased(app), !enabledApps.contains(appKey(app)) {
            let status = tree.setBool("AXManualAccessibility", on: app)
            failures.append("AXManualAccessibility set \(Self.name(status))")
            if status == .success {
                enabledApps.insert(appKey(app))
                for retry in 1...Self.retryAttempts {
                    sleep(Self.retryInterval)
                    if let window = attempt(kAXFocusedWindowAttribute, label: "focused retry \(retry)") {
                        return .found(window, via: "focused window after AXManualAccessibility")
                    }
                }
            }
        }
        return .notFound(reason: failures.joined(separator: "; "))
    }

    static func name(_ error: AXError) -> String {
        switch error {
        case .success: return "ok"
        case .failure: return "failure(-25200)"
        case .illegalArgument: return "illegalArgument(-25201)"
        case .invalidUIElement: return "invalidUIElement(-25202)"
        case .invalidUIElementObserver: return "invalidUIElementObserver(-25203)"
        case .cannotComplete: return "cannotComplete(-25204)"
        case .attributeUnsupported: return "attributeUnsupported(-25205)"
        case .actionUnsupported: return "actionUnsupported(-25206)"
        case .notificationUnsupported: return "notificationUnsupported(-25207)"
        case .notImplemented: return "notImplemented(-25208)"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered(-25209)"
        case .notificationNotRegistered: return "notificationNotRegistered(-25210)"
        case .apiDisabled: return "apiDisabled(-25211)"
        case .noValue: return "noValue(-25212)"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported(-25213)"
        case .notEnoughPrecision: return "notEnoughPrecision(-25214)"
        @unknown default: return "error(\(error.rawValue))"
        }
    }
}

/// An AX call's error code, wrapped because `AXError` is not an `Error`.
struct AXFailure: Error {
    let code: AXError
}
