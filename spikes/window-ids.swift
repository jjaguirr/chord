#!/usr/bin/env swift
import Foundation

func fail(_ reason: String, _ path: String) -> Never {
  fputs("FAIL: \(reason); fail path: \(path)\n", stderr)
  exit(1)
}
func windows() throws -> [(String, String)] {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  p.arguments = ["aerospace", "list-windows", "--all", "--format", "%{window-id} %{app-name}"]
  let out = Pipe()
  p.standardOutput = out
  p.standardError = Pipe()
  try p.run()
  p.waitUntilExit()
  guard p.terminationStatus == 0 else {
    throw NSError(
      domain: "AeroSpace", code: Int(p.terminationStatus),
      userInfo: [NSLocalizedDescriptionKey: "server command failed"])
  }
  let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  return text.split(separator: "\n").compactMap { row in
    let fields = row.split(separator: " ", maxSplits: 1)
    guard fields.count == 2 else { return nil }
    return (String(fields[0]), String(fields[1]))
  }
}
do {
  let before = try windows()
  guard Set(before.map(\.1)).count >= 3 else {
    fail(
      "need windows from at least three apps; observed \(Set(before.map(\.1)).count)",
      "open three disposable test apps and rerun")
  }
  guard Set(before.map(\.0)).count == before.count else {
    fail("window IDs collide within one sample", "inspect substrate ID mapping")
  }
  Thread.sleep(forTimeInterval: 2)
  let after = try windows()
  guard Set(after.map(\.0)).count == after.count else {
    fail("window IDs collide in after sample", "inspect substrate ID mapping")
  }
  let afterByID = Dictionary(after.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
  guard before.allSatisfy({ afterByID[$0.0] == $0.1 }) else {
    fail(
      "IDs or app associations changed during 2-second idle interval",
      "inspect ID stability and app-window lifecycle")
  }
  print(
    "PASS: \(before.count) IDs unique and stable across \(Set(before.map(\.1)).count) apps for 2s; threshold no collisions or changes"
  )
} catch {
  fail(
    "could not query AeroSpace: \(error)",
    "install the pinned AeroSpace build, start its server, and rerun")
}
