import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


REPO_ROOT = Path(__file__).parents[2]
MANIFEST_PATH = REPO_ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
ANDROID_NAMESPACE = "{http://schemas.android.com/apk/res/android}"


class AndroidManifestTest(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = ET.parse(MANIFEST_PATH).getroot()

    def test_release_build_can_access_the_network(self) -> None:
        permissions = {
            node.get(f"{ANDROID_NAMESPACE}name")
            for node in self.manifest.findall("uses-permission")
        }

        self.assertIn("android.permission.INTERNET", permissions)

    def test_test_backend_cleartext_transport_is_explicitly_enabled(self) -> None:
        application = self.manifest.find("application")

        self.assertIsNotNone(application)
        self.assertEqual(
            application.get(f"{ANDROID_NAMESPACE}usesCleartextTraffic"),
            "true",
        )


if __name__ == "__main__":
    unittest.main()
