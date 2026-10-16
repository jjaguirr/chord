"""Negative tests for check_invariants.py: each planted violation must fail.

Run from the repo root: python3 -m unittest discover -s scripts -p 'test_*.py'
"""
import shutil
import tempfile
import unittest
from pathlib import Path

import check_invariants

REPO = Path(__file__).resolve().parent.parent


class InvariantChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.root = self.tmp / "repo"
        # Start from the real sources so the baseline is the shipped code.
        shutil.copytree(REPO / "Sources", self.root / "Sources")
        shutil.copy(REPO / "Package.swift", self.root / "Package.swift")
        (self.root / "spikes").mkdir()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def violations(self):
        return check_invariants.check(self.root)

    def assertFlagged(self, check_id, fragment=""):
        hits = [v for v in self.violations() if v.startswith(f"[{check_id}]") and fragment in v]
        self.assertTrue(hits, f"expected [{check_id}] violation, got {self.violations()}")

    def assertClean(self):
        self.assertEqual(self.violations(), [])

    def test_shipped_sources_are_clean(self):
        self.assertClean()

    # a: ChordCore imports only the Swift standard library.
    def test_core_importing_foundation_fails(self):
        self.write("Sources/ChordCore/Leak.swift", "import Foundation\n")
        self.assertFlagged("a-core-stdlib-only", "Foundation")

    def test_core_importing_appkit_with_attribute_fails(self):
        self.write("Sources/ChordCore/Leak.swift", "@_implementationOnly import AppKit\n")
        self.assertFlagged("a-core-stdlib-only", "AppKit")

    def test_core_importing_third_party_submodule_fails(self):
        self.write("Sources/ChordCore/Leak.swift", "internal import SomeLib.Sub\n")
        self.assertFlagged("a-core-stdlib-only", "SomeLib")

    def test_commented_import_in_core_is_not_flagged(self):
        self.write("Sources/ChordCore/Note.swift", "// import Foundation would leak here\n")
        self.assertClean()

    def test_importing_swift_stdlib_in_core_is_allowed(self):
        self.write("Sources/ChordCore/Ok.swift", "import Swift\n")
        self.assertClean()

    # b: window mutation only in the Executor.
    def test_frame_mutation_outside_executor_fails(self):
        self.write("Sources/Chord/Animator.swift", "func step(w: W) { w.setFrame(r) }\n")
        self.assertFlagged("b-window-mutation", "setFrame")

    def test_raise_outside_executor_fails(self):
        self.write("Sources/Chord/Focus.swift", "func f(w: W) { w.raise() }\n")
        self.assertFlagged("b-window-mutation", "raise")

    def test_move_outside_executor_fails(self):
        self.write("Sources/ChordCore/Pick.swift", "func f(w: W) { w.move(to: p) }\n")
        self.assertFlagged("b-window-mutation", "move")

    def test_frame_property_assignment_outside_executor_fails(self):
        self.write("Sources/Chord/Animator.swift", "func step(window: W) { window.frame = rect }\n")
        self.assertFlagged("b-window-mutation", "frame")

    def test_frame_inout_argument_outside_executor_fails(self):
        self.write("Sources/Chord/Animator.swift", "func step(w: W) { update(&w.frame) }\n")
        self.assertFlagged("b-window-mutation", "frame")

    def test_nested_frame_property_assignment_outside_executor_fails(self):
        self.write("Sources/Chord/Animator.swift", "func step(window: W) { window.frame.origin.x = 1 }\n")
        self.assertFlagged("b-window-mutation", "frame")
    def test_optional_chained_frame_mutations_outside_executor_fail(self):
        self.write("Sources/Chord/Animator.swift", "func step(window: W) { window?.frame = rect }\n")
        self.assertFlagged("b-window-mutation", "frame")
        self.write("Sources/Chord/Animator.swift", "func step(window: W) { update(&window?.frame) }\n")
        self.assertFlagged("b-window-mutation", "frame")
    def test_nested_frame_compound_assignment_outside_executor_fails(self):
        self.write("Sources/Chord/Animator.swift", "func step(window: W) { window.frame.origin.x -= 1 }\n")
        self.assertFlagged("b-window-mutation", "frame")


    def test_frame_reads_and_comparisons_are_allowed(self):
        self.write(
            "Sources/Chord/Animator.swift",
            "let frame = window.frame\n"
            "if window.frame == rect { use(frame) }\n"
            "if window.frame != rect { use(frame) }\n"
            "if window.frame.origin.x <= 1 { use(frame) }\n"
            "if window.frame.origin.x >= 1 { use(frame) }\n",
        )
        self.assertClean()


    def test_ax_position_write_outside_executor_fails(self):
        self.write(
            "Sources/Chord/Ax.swift",
            "AXUIElementSetAttributeValue(element, kAXPositionAttribute, value)\n",
        )
        self.assertFlagged("b-window-mutation", "AXUIElementSetAttributeValue")
    def test_ax_raise_action_outside_executor_fails(self):
        self.write(
            "Sources/Chord/Ax.swift",
            "AXUIElementPerformAction(element, kAXRaiseAction as CFString)\n",
        )
        self.assertFlagged("b-window-mutation", "AXUIElementPerformAction")


    def test_ax_position_read_outside_executor_is_allowed(self):
        self.write(
            "Sources/Chord/Ax.swift",
            "AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &value)\n",
        )
        self.assertClean()

    def test_string_containing_line_comment_does_not_hide_window_mutation(self):
        self.write(
            "Sources/Chord/Animator.swift",
            'let url = "https://example.invalid"; window.setFrame(rect)\n',
        )
        self.assertFlagged("b-window-mutation", "setFrame")

    def test_mutation_inside_executor_is_allowed(self):
        self.write("Sources/Chord/Executor/Apply.swift", "func apply(w: W) { w.setFrame(r); w.raise() }\n")
        self.assertClean()

    def test_mutation_word_in_comment_is_not_flagged(self):
        self.write("Sources/Chord/Doc.swift", "// the Executor will raise and move windows\n")
        self.assertClean()

    # c: the socket client is used only by the backend.
    def test_socket_call_outside_backend_fails(self):
        self.write("Sources/Chord/Input.swift", "let fd = socket(AF_UNIX, SOCK_STREAM, 0)\n")
        self.assertFlagged("c-socket-client", "socket")

    def test_socket_client_type_outside_backend_fails(self):
        self.write("Sources/Chord/Agents.swift", "let c = AeroSpaceSocket()\n")
        self.assertFlagged("c-socket-client", "AeroSpaceSocket")

    def test_network_import_outside_backend_fails(self):
        self.write("Sources/Chord/Net.swift", "import Network\n")
        self.assertFlagged("c-socket-client", "Network")

    def test_socket_client_inside_backend_is_allowed(self):
        self.write(
            "Sources/Chord/Backend/AeroSpaceClient.swift",
            "import Network\nlet c = AeroSpaceSocket()\nlet fd = socket(AF_UNIX, SOCK_STREAM, 0)\n",
        )
        self.assertClean()

    # d: nothing under Sources/ or Package.swift reaches into spikes/.
    def test_source_path_reference_to_spikes_fails(self):
        self.write("Sources/Chord/Probe.swift", 'let p = "spikes/probe.swift"\n')
        self.assertFlagged("d-spikes-isolation", "spikes")

    def test_import_of_spike_module_fails(self):
        self.write("spikes/probe.swift", "let x = 1\n")
        self.write("Sources/Chord/Use.swift", "import probe\n")
        self.assertFlagged("d-spikes-isolation", "probe")

    def test_package_target_pointing_into_spikes_fails(self):
        self.write(
            "Package.swift",
            'import PackageDescription\n'
            'let package = Package(name: "Chord", targets: [.target(name: "P", path: "spikes/p")])\n',
        )
        self.assertFlagged("d-spikes-isolation", "Package.swift")
    def test_package_target_path_equal_to_spikes_fails(self):
        self.write(
            "Package.swift",
            'import PackageDescription\n'
            'let package = Package(name: "Chord", targets: [.target(name: "P", path: "spikes")])\n',
        )
        self.assertFlagged("d-spikes-isolation", "Package.swift")
    def test_spikes_directory_contents_are_not_scanned(self):
        self.write("spikes/probe.swift", 'import Foundation\nlet p = "spikes/x"\n')
        self.assertClean()

    def test_spikes_word_in_comment_is_not_flagged(self):
        self.write("Sources/Chord/Doc.swift", "// do not import spikes\n")
        self.assertClean()

    def test_forbidden_calls_in_strings_and_nested_comments_are_ignored(self):
        self.write(
            "Sources/Chord/Doc.swift",
            'let a = "window.setFrame(rect); socket(AF_UNIX)"; '
            'let b = #"raise(); import Foundation"#\n'
            '/* outer /* window.frame = rect */ still a comment */\n',
        )
        self.assertClean()

    def test_multiline_string_call_text_is_ignored(self):
        self.write(
            "Sources/Chord/Doc.swift",
            'let text = """\nwindow.setFrame(rect)\nAeroSpaceSocket()\n"""\n',
        )
        self.assertClean()

    def test_interpolated_code_is_still_scanned(self):
        self.write(
            "Sources/Chord/Animator.swift",
            'let text = "frame: \\(window.setFrame(rect))"\n',
        )
        self.assertFlagged("b-window-mutation", "setFrame")

    def test_raw_string_spike_target_path_fails(self):
        self.write(
            "Package.swift",
            'import PackageDescription\n'
            'let package = Package(name: "Chord", targets: [.target(name: "P", path: #"/spikes/probe"#)])\n',
        )
        self.assertFlagged("d-spikes-isolation", "Package.swift")

    def test_multiline_spike_target_path_fails(self):
        self.write(
            "Package.swift",
            'import PackageDescription\n'
            'let package = Package(name: "Chord", targets: [.target(name: "P", path: """\nspikes\n""")])\n',
        )
        self.assertFlagged("d-spikes-isolation", "Package.swift")

    def test_property_style_frame_compound_mutation_fails(self):
        self.write(
            "Sources/Chord/Animator.swift",
            "func step(window: W) { window?.frame.origin.x *= 2 }\n",
        )
        self.assertFlagged("b-window-mutation", "frame")

    def test_unqualified_frame_property_assignment_fails(self):
        self.write("Sources/Chord/Animator.swift", "func step() { frame.origin.x = 1 }\n")
        self.assertFlagged("b-window-mutation", "frame")

    def test_wrapping_compound_frame_mutations_fail(self):
        for operator in ("&+=", "&-=", "&*=", "&/=", "&%="):
            with self.subTest(operator=operator):
                self.write(
                    "Sources/Chord/Animator.swift",
                    f"func step(window: W) {{ window.frame.origin.x {operator} 1 }}\n",
                )
                self.assertFlagged("b-window-mutation", "frame")

    def test_nested_inout_frame_path_fails(self):
        self.write(
            "Sources/Chord/Animator.swift",
            "func step(holder: H) { update(&holder.window.frame) }\n",
        )
        self.assertFlagged("b-window-mutation", "frame")

    def test_concatenated_spike_target_path_fails(self):
        self.write(
            "Package.swift",
            'import PackageDescription\n'
            'let package = Package(name: "Chord", targets: [.target(name: "P", path: "sp" + "ikes/probe")])\n',
        )
        self.assertFlagged("d-spikes-isolation", "Package.swift")

    def test_import_violations_report_import_line(self):
        self.write("Sources/ChordCore/Leak.swift", "\n\nimport Foundation\n")
        self.write("Sources/Chord/Net.swift", "\n\nimport Network\n")
        self.write("spikes/probe.swift", "let value = 1\n")
        self.write("Sources/Chord/Use.swift", "\n\nimport probe\n")
        violations = self.violations()
        self.assertTrue(any("[a-core-stdlib-only] Sources/ChordCore/Leak.swift:3:" in v for v in violations))
        self.assertTrue(any("[c-socket-client] Sources/Chord/Net.swift:3:" in v for v in violations))
        self.assertTrue(any("[d-spikes-isolation] Sources/Chord/Use.swift:3:" in v for v in violations))



if __name__ == "__main__":
    unittest.main()
