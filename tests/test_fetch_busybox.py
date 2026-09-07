import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class FetchBusyboxTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ("env.sh", "fetch-busybox.sh"):
            shutil.copy2(ROOT / "scripts" / name, scripts / name)

        self.upstream = self.root / "upstream.tar.bz2"
        payload = b"locked busybox source\n"
        with tarfile.open(self.upstream, "w:bz2") as archive:
            info = tarfile.TarInfo("busybox-1.38.0/applets/README")
            info.size = len(payload)
            archive.addfile(info, io.BytesIO(payload))
        self.digest = hashlib.sha256(self.upstream.read_bytes()).hexdigest()

    def tearDown(self):
        self.tempdir.cleanup()

    def run_fetch(self):
        env = os.environ.copy()
        env.update(
            {
                "BB_URL": (self.root / "不存在.tar.bz2").as_uri(),
                "BB_FALLBACK_URL": self.upstream.as_uri(),
                "BB_SHA256": self.digest,
            }
        )
        return subprocess.run(
            ["bash", str(self.root / "scripts" / "fetch-busybox.sh")],
            cwd=self.root,
            env=env,
            check=False,
            text=True,
            capture_output=True,
        )

    def test_primary_failure_uses_verified_fallback(self):
        result = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        marker = self.root / "src" / "busybox-1.38.0" / ".bb-src-ok"
        self.assertIn(f"sha256={self.digest}", marker.read_text())

    def test_corrupt_cached_tarball_is_replaced(self):
        cache = self.root / "src" / "busybox-1.38.0.tar.bz2"
        cache.parent.mkdir()
        cache.write_bytes(b"corrupt cache")

        result = self.run_fetch()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(hashlib.sha256(cache.read_bytes()).hexdigest(), self.digest)
        self.assertIn("删除校验失败的缓存", result.stderr)


if __name__ == "__main__":
    unittest.main()
