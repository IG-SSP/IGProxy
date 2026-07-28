import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == "posix", "hub registry uses Linux file locking")
class ClusterFeatureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.state = root / "state"
        self.config = root / "config.json"
        self.config.write_text(
            json.dumps(
                {
                    "deployment_role": "hub",
                    "client_servers": [
                        {
                            "id": "manual",
                            "label": "Ручной",
                            "url": "https://t.me/proxy?server=manual.example&port=443&secret=abc",
                            "enabled": True,
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        os.environ["IGPROXY_HUB_STATE"] = str(self.state)
        os.environ["GOTELEGRAM_CONFIG"] = str(self.config)
        os.environ["IGPROXY_CONFIG_LOCK"] = str(root / "config.lock")
        spec = importlib.util.spec_from_file_location(
            "igproxy_hub_test", ROOT / "cluster" / "hub_server.py"
        )
        self.hub = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        sys.modules[spec.name] = self.hub
        spec.loader.exec_module(self.hub)

    def tearDown(self):
        self.temp.cleanup()

    def test_one_time_enrollment_syncs_managed_server_without_raw_secrets(self):
        code, _ = self.hub.create_enrollment_code(600)
        proxy_url = "https://t.me/proxy?server=node.example&port=8443&secret=abcdef"
        result = self.hub.enroll_node(
            {
                "pairing_code": code,
                "install_id": "server-one",
                "label": "Финляндия",
                "proxy_url": proxy_url,
                "status": {"telemt": True},
            }
        )
        registry_text = self.hub.REGISTRY_PATH.read_text(encoding="utf-8")
        self.assertNotIn(code, registry_text)
        self.assertNotIn(result["node_token"], registry_text)

        config = json.loads(self.config.read_text(encoding="utf-8"))
        self.assertEqual(config["client_servers"][0]["id"], "manual")
        managed = config["client_servers"][1]
        self.assertTrue(managed["managed"])
        self.assertEqual(managed["label"], "Финляндия")
        self.assertEqual(managed["url"], proxy_url)

        with self.assertRaises(PermissionError):
            self.hub.enroll_node(
                {
                    "pairing_code": code,
                    "install_id": "server-two",
                    "label": "Повтор",
                    "proxy_url": proxy_url,
                }
            )

    def test_heartbeat_requires_token_and_updates_public_status(self):
        code, _ = self.hub.create_enrollment_code(600)
        proxy_url = "https://t.me/proxy?server=198.51.100.7&port=9443&secret=abcdef"
        result = self.hub.enroll_node(
            {
                "pairing_code": code,
                "install_id": "server-two",
                "label": "Амстердам",
                "proxy_url": proxy_url,
            }
        )
        with self.assertRaises(PermissionError):
            self.hub.heartbeat({}, "Bearer wrong")
        current = self.hub.now_epoch()
        self.hub.now_epoch = lambda: current + self.hub.MIN_HEARTBEAT_INTERVAL + 1
        heartbeat = self.hub.heartbeat(
            {"status": {"telemt": True, "load_1m": 0.2}},
            f"Bearer {result['node_token']}",
        )
        self.assertTrue(heartbeat["ok"])
        config = json.loads(self.config.read_text(encoding="utf-8"))
        self.assertTrue(config["cluster_nodes"][0]["status"]["telemt"])

    def test_node_agent_refuses_all_http_redirects(self):
        spec = importlib.util.spec_from_file_location(
            "igproxy_node_test", ROOT / "cluster" / "node_agent.py"
        )
        node = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(node)
        handler = node.NoRedirectHandler()
        self.assertIsNone(
            handler.redirect_request(None, None, 302, "Found", {}, "https://evil.example/")
        )


if __name__ == "__main__":
    unittest.main()
