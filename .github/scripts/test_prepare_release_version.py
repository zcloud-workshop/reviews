"""验证标签作为发布版本来源，以及版本改写不会破坏其他配置。"""

import tempfile
import unittest
from pathlib import Path

from prepare_release_version import prepare_release_version


class ReleaseVersionTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.pubspec = Path(directory.name) / "pubspec.yaml"
        self.source = "name: reviews\n# 本地默认版本\nversion: 0.1.0+2\nenvironment:\n  sdk: ^3.6.2\n"
        self.pubspec.write_text(self.source, encoding="utf-8")

    def test_发布标签覆盖旧版本并保留其他配置(self):
        metadata = prepare_release_version(self.pubspec, "v0.1.1")

        self.assertEqual(metadata, {"app_name": "reviews", "version": "0.1.1", "release_tag": "v0.1.1"})
        self.assertEqual(self.pubspec.read_text(encoding="utf-8"), self.source.replace("0.1.0+2", "0.1.1"))

    def test_连续发布无需预先修改文件版本(self):
        for tag, version in (("v0.1.1", "0.1.1"), ("v0.1.2", "0.1.2"), ("v0.2.0-beta.1", "0.2.0-beta.1")):
            with self.subTest(tag=tag):
                self.assertEqual(prepare_release_version(self.pubspec, tag)["version"], version)
                self.assertIn(f"version: {version}\n", self.pubspec.read_text(encoding="utf-8"))

    def test_非法标签不修改文件(self):
        for tag in ("", "0.1.1", "v0.1", "v0.1.1+2", "v00.1.1", "v0.1.1-beta..1", "v0.1.1000", "v2100.0.0"):
            with self.subTest(tag=tag):
                with self.assertRaises(ValueError):
                    prepare_release_version(self.pubspec, tag)
                self.assertEqual(self.pubspec.read_text(encoding="utf-8"), self.source)

    def test_缺少或重复版本字段不修改文件(self):
        for source in ("name: reviews\n", "name: reviews\nversion: 0.1.0\nversion: 0.1.1\n"):
            with self.subTest(source=source):
                self.pubspec.write_text(source, encoding="utf-8")
                with self.assertRaises(ValueError):
                    prepare_release_version(self.pubspec, "v0.1.2")
                self.assertEqual(self.pubspec.read_text(encoding="utf-8"), source)


if __name__ == "__main__":
    unittest.main()
