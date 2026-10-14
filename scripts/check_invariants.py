#!/usr/bin/env python3
"""Mechanical checks for the AGENTS.md hard invariants that are visible in text.

Usage: scripts/check_invariants.py [repo-root]

Prints one line per violation and exits 1; exits 0 when clean.

Checks (see AGENTS.md "Definition of done"):
  a-core-stdlib-only  Sources/ChordCore imports only the Swift standard library.
  b-window-mutation   Window-mutating calls appear only in Sources/Chord/Executor/.
  c-socket-client     The workspace-backend socket client is used only in
                      Sources/Chord/Backend/.
  d-spikes-isolation  Nothing under Sources/ or Package.swift references the spikes tree.

Limits: only line comments (`//`) are stripped before matching. A block comment
that mentions a banned call is a false positive (stricter, acceptable). A `//`
inside a string literal hides the rest of that line; that is a known gap.
"""
import re
import sys
from pathlib import Path

EXECUTOR = "Sources/Chord/Executor"
BACKEND = "Sources/Chord/Backend"

IMPORT = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:(?:public|internal|package|private|fileprivate)\s+)?"
    r"import\s+(?:(?:struct|class|enum|protocol|typealias|func|var|let)\s+)?"
    r"([A-Za-z_]\w*)"
)

WINDOW_MUTATION = re.compile(
    r"\b(?:setFrame|setFrameOrigin|setFrameSize|setPosition|setSize|setContentSize"
    r"|AXUIElementSetAttributeValue|AXRaiseAction|makeKeyAndOrderFront|orderFront"
    r"|raise|moveTo|move|resize)\s*\("
    r"|\bkAX(?:Position|Size|Raise|Main)\w*"
    r"|\b(?:\w+\.)+frame(?:\.\w+)*\s*=(?!=|>)"
    r"|\bframe\.\w+(?:\.\w+)*\s*=(?!=|>)"
    r"|&\s*(?:\w+\.)*frame\b"
)

SOCKET_CLIENT = re.compile(
    r"\b(?:AF_UNIX|sockaddr_un|NWConnection|NWEndpoint|NWParameters"
    r"|SocketClient|AeroSpaceSocket|AeroSpaceClient)\b"
    r"|\b(?:socket|connect)\s*\("
)

SPIKE_REFERENCE = re.compile(r"\bspikes\b")


def swift_files(root, under):
    base = root / under
    if not base.is_dir():
        return []
    return sorted(base.rglob("*.swift"))


def code_lines(path):
    text = path.read_text(encoding="utf-8")
    for number, line in enumerate(text.splitlines(), start=1):
        yield number, re.sub(r"//.*", "", line)


def under(path, root, prefix):
    return path.relative_to(root).as_posix().startswith(prefix + "/")


def check(root):
    root = Path(root).resolve()
    violations = []

    def add(check_id, path, number, message):
        rel = path.relative_to(root).as_posix()
        violations.append(f"[{check_id}] {rel}:{number}: {message}")

    # a: ChordCore is stdlib-only.
    for path in swift_files(root, "Sources/ChordCore"):
        for number, line in code_lines(path):
            match = IMPORT.match(line)
            if match and match.group(1) != "Swift":
                add("a-core-stdlib-only", path, number,
                    f"ChordCore imports {match.group(1)}; only the Swift standard library is allowed")

    # b: only the Executor changes windows.
    for path in swift_files(root, "Sources"):
        if under(path, root, EXECUTOR):
            continue
        for number, line in code_lines(path):
            match = WINDOW_MUTATION.search(line)
            if match:
                add("b-window-mutation", path, number,
                    f"window-mutating call `{match.group(0).strip()}` outside {EXECUTOR}")

    # c: the workspace-backend socket client is used only by the backend.
    for path in swift_files(root, "Sources"):
        if under(path, root, BACKEND):
            continue
        for number, line in code_lines(path):
            match = SOCKET_CLIENT.search(line)
            if match:
                add("c-socket-client", path, number,
                    f"socket client `{match.group(0).strip()}` outside {BACKEND}")
            imported = IMPORT.match(line)
            if imported and (imported.group(1) == "Network" or "Socket" in imported.group(1)):
                add("c-socket-client", path, number,
                    f"imports {imported.group(1)} outside {BACKEND}")

    # d: Sources and Package.swift never reach into spikes/.
    spikes = root / "spikes"
    spike_modules = {"spikes"}
    if spikes.is_dir():
        spike_modules |= {entry.stem for entry in spikes.iterdir()}
    candidates = swift_files(root, "Sources")
    if (root / "Package.swift").is_file():
        candidates.append(root / "Package.swift")
    for path in candidates:
        for number, line in code_lines(path):
            if SPIKE_REFERENCE.search(line):
                add("d-spikes-isolation", path, number, "references spikes")
            imported = IMPORT.match(line)
            if imported and imported.group(1) in spike_modules:
                add("d-spikes-isolation", path, number,
                    f"imports spike module {imported.group(1)}")

    return violations


def main(argv):
    default_root = Path(__file__).resolve().parent.parent
    root = Path(argv[1]) if len(argv) > 1 else default_root
    violations = check(root)
    for line in violations:
        print(line)
    if violations:
        print(f"{len(violations)} invariant violation(s)")
        return 1
    print("invariant checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
