"""当前文档入口不能重新引用退役补丁或产生本地死链。"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CURRENT_DOCS = [
    ROOT / "README.md",
    *sorted((ROOT / "docs").glob("*.md")),
    ROOT / "patches/README.md",
    ROOT / "patches/cosmo/README.md",
    ROOT / "toolchain/README.md",
]


class DocumentationTests(unittest.TestCase):
    def test_local_links_exist(self):
        failures = []
        for document in CURRENT_DOCS:
            for target in re.findall(r"\[[^]]*\]\(([^)]+)\)", document.read_text()):
                if "://" in target or target.startswith("#"):
                    continue
                path = (document.parent / target.split("#", 1)[0]).resolve()
                if not path.exists():
                    failures.append(f"{document.relative_to(ROOT)} -> {target}")
        self.assertEqual(failures, [])

    def test_retired_names_only_appear_as_history_explanation(self):
        allowed = ROOT / "patches/cosmo/README.md"
        retired = ["busybox-cosmo-full.patch", "busybox-applet-restore.patch",
                   "VERIFICATION-MATRIX.md", "APPLE-SILICON-TEST.md"]
        failures = []
        for document in CURRENT_DOCS:
            if document == allowed:
                continue
            text = document.read_text()
            for name in retired:
                if name in text:
                    failures.append(f"{document.relative_to(ROOT)}: {name}")
        self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main()
