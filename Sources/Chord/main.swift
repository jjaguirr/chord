import AppKit

// Menu-bar agent: no Dock icon. LSUIElement in the bundle's Info.plist does the same
// for the packaged app; this policy covers `swift run` as well.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
// NSApplication holds its delegate weakly, so keep a strong global reference.
let shell = ChordShell()
application.delegate = shell
application.run()
