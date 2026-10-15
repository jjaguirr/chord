#!/usr/bin/env python3
"""Mechanical checks for the AGENTS.md hard invariants that are visible in text.

Usage: scripts/check_invariants.py [repo-root]

Prints one line per violation and exits 1; exits 0 when clean.
"""
import sys
from pathlib import Path

EXECUTOR = "Sources/Chord/Executor"
BACKEND = "Sources/Chord/Backend"
WINDOW_CALLS = {
    "setFrame", "setFrameOrigin", "setFrameSize", "setPosition", "setSize",
    "setContentSize", "AXUIElementSetAttributeValue", "AXRaiseAction",
    "makeKeyAndOrderFront", "orderFront", "raise", "moveTo", "move", "resize",
}
SOCKET_TYPES = {
    "AF_UNIX", "sockaddr_un", "NWConnection", "NWEndpoint", "NWParameters",
    "SocketClient", "AeroSpaceSocket", "AeroSpaceClient",
}
IMPORT_KINDS = {"struct", "class", "enum", "protocol", "typealias", "func", "var", "let"}


class SwiftScanner:
    """Small lexical scanner: code tokens, string contents, and source locations."""

    def __init__(self, text):
        self.text = text
        self.index = 0
        self.line = 1
        self.tokens = []

    def emit(self, kind, value, line):
        self.tokens.append((kind, value, line))

    def scan_string(self):
        start = self.index
        hashes = 0
        while self.index < len(self.text) and self.text[self.index] == "#":
            hashes += 1
            self.index += 1
        if self.index >= len(self.text) or self.text[self.index] != '"':
            self.index = start
            return False
        triple = self.text.startswith('"""', self.index)
        delimiter = '"""' if triple else '"'
        self.index += len(delimiter)
        line = self.line
        content = []
        while self.index < len(self.text):
            if self.text.startswith(delimiter + "#" * hashes, self.index):
                self.emit("string", "".join(content), line)
                self.index += len(delimiter) + hashes
                return True
            if self.text[self.index] == "\n":
                content.append("\n")
                self.line += 1
                self.index += 1
                continue
            escape = "\\" + "#" * hashes
            if self.text.startswith(escape, self.index):
                next_index = self.index + len(escape)
                if self.text.startswith("(", next_index):
                    self.emit("string", "".join(content), line)
                    self.index = next_index + 1
                    self.scan_code(interpolation=True)
                    content = []
                    continue
                if self.text.startswith(delimiter, next_index):
                    content.append(delimiter)
                    self.index = next_index + len(delimiter)
                    continue
            if self.text[self.index] == "\\" and hashes == 0:
                if self.text.startswith("\\(", self.index):
                    self.emit("string", "".join(content), line)
                    self.index += 2
                    self.scan_code(interpolation=True)
                    content = []
                    continue
                if self.index + 1 < len(self.text):
                    content.append(self.text[self.index + 1])
                    if self.text[self.index + 1] == "\n":
                        self.line += 1
                    self.index += 2
                    continue
            content.append(self.text[self.index])
            self.index += 1
        self.emit("string", "".join(content), line)
        return True

    def scan_code(self, interpolation=False):
        depth = 0
        while self.index < len(self.text):
            char = self.text[self.index]
            if char.isspace():
                if char == "\n":
                    self.line += 1
                self.index += 1
                continue
            if self.text.startswith("//", self.index):
                end = self.text.find("\n", self.index + 2)
                self.index = len(self.text) if end < 0 else end
                continue
            if self.text.startswith("/*", self.index):
                self.index += 2
                nested = 1
                while self.index < len(self.text) and nested:
                    if self.text.startswith("/*", self.index):
                        nested += 1
                        self.index += 2
                    elif self.text.startswith("*/", self.index):
                        nested -= 1
                        self.index += 2
                    else:
                        if self.text[self.index] == "\n":
                            self.line += 1
                        self.index += 1
                continue
            if interpolation and char == ")":
                if depth == 0:
                    self.index += 1
                    return
                depth -= 1
            elif interpolation and char == "(":
                depth += 1
            if char == "#" or char == '"':
                if self.scan_string():
                    continue
            line = self.line
            if char.isalpha() or char == "_":
                start = self.index
                self.index += 1
                while self.index < len(self.text) and (self.text[self.index].isalnum() or self.text[self.index] == "_"):
                    self.index += 1
                self.emit("identifier", self.text[start:self.index], line)
                continue
            if self.text.startswith("<<=", self.index) or self.text.startswith(">>=", self.index):
                self.emit("punct", self.text[self.index:self.index + 3], line)
                self.index += 3
                continue
            if self.text.startswith(("?.", "==", "!=", "<=", ">=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "&&", "||", "->"), self.index):
                self.emit("punct", self.text[self.index:self.index + 2], line)
                self.index += 2
                continue
            self.emit("punct", char, line)
            self.index += 1

    def scan(self):
        self.scan_code()
        return self.tokens


def swift_files(root, under):
    base = root / under
    if not base.is_dir():
        return []
    return sorted(base.rglob("*.swift"))


def under(path, root, prefix):
    return path.relative_to(root).as_posix().startswith(prefix + "/")


def tokens(path):
    return SwiftScanner(path.read_text(encoding="utf-8")).scan()


def imports(items):
    """Yield imported module names; comments and literals are absent from code tokens."""
    values = [value for kind, value, _ in items if kind != "string"]
    for index, value in enumerate(values):
        if value != "import":
            continue
        cursor = index + 1
        if cursor < len(values) and values[cursor] in IMPORT_KINDS:
            cursor += 1
        if cursor < len(values) and values[cursor].isidentifier():
            yield values[cursor]


def window_mutations(items):
    code = [token for token in items if token[0] != "string"]
    values = [value for _, value, _ in code]
    for index, (kind, value, line) in enumerate(code):
        if value in WINDOW_CALLS and index + 1 < len(code) and values[index + 1] == "(":
            yield value, line
        if value == "AXUIElementPerformAction" and index + 1 < len(code):
            end = next((j for j in range(index + 1, len(code)) if values[j] == ")"), len(code))
            if "kAXRaiseAction" in values[index + 1:end]:
                yield value, line
        if value != "frame" or kind != "identifier":
            continue
        previous = values[index - 1] if index else ""
        if previous not in {".", "?."}:
            continue
        cursor = index + 1
        while cursor + 1 < len(code) and values[cursor] in {".", "?."} and code[cursor + 1][0] == "identifier":
            cursor += 2
        if cursor < len(code) and values[cursor] in {"=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>="}:
            yield "frame", line
        if "&" in values[max(0, index - 4):index]:
            yield "frame", line


def has_spike_reference(items):
    for kind, value, _ in items:
        if kind == "string" and "spikes" in value:
            return True
    return False


def check(root):
    root = Path(root).resolve()
    violations = []

    def add(check_id, path, number, message):
        rel = path.relative_to(root).as_posix()
        violations.append(f"[{check_id}] {rel}:{number}: {message}")

    for path in swift_files(root, "Sources/ChordCore"):
        for module in imports(tokens(path)):
            if module != "Swift":
                add("a-core-stdlib-only", path, 1,
                    f"ChordCore imports {module}; only the Swift standard library is allowed")

    for path in swift_files(root, "Sources"):
        if under(path, root, EXECUTOR):
            continue
        for mutation, line in window_mutations(tokens(path)):
            add("b-window-mutation", path, line,
                f"window-mutating call `{mutation}` outside {EXECUTOR}")

    for path in swift_files(root, "Sources"):
        if under(path, root, BACKEND):
            continue
        items = tokens(path)
        code = [token for token in items if token[0] != "string"]
        for index, (kind, value, line) in enumerate(code):
            if kind == "identifier" and value in SOCKET_TYPES:
                add("c-socket-client", path, line, f"socket client `{value}` outside {BACKEND}")
            if kind == "identifier" and value in {"socket", "connect"} and index + 1 < len(code) and code[index + 1][1] == "(":
                add("c-socket-client", path, line, f"socket client `{value}` outside {BACKEND}")
        for module in imports(items):
            if module == "Network" or "Socket" in module:
                add("c-socket-client", path, 1, f"imports {module} outside {BACKEND}")

    spikes = root / "spikes"
    spike_modules = {"spikes"}
    if spikes.is_dir():
        spike_modules |= {entry.stem for entry in spikes.iterdir()}
    candidates = swift_files(root, "Sources")
    package = root / "Package.swift"
    if package.is_file():
        candidates.append(package)
    for path in candidates:
        items = tokens(path)
        if has_spike_reference(items):
            line = next((line for kind, value, line in items if kind == "string" and "spikes" in value), 1)
            add("d-spikes-isolation", path, line, "references spikes")
        for module in imports(items):
            if module in spike_modules:
                add("d-spikes-isolation", path, 1, f"imports spike module {module}")

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
