import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BOT_PATH = ROOT / "gotelegram-bot" / "bot.py"
CATALOG_PATH = ROOT / "templates_catalog.json"
INSTALL_PATH = ROOT / "install.sh"
ADMIN_INDEX_PATH = ROOT / "admin-web" / "static" / "index.html"
ADMIN_JS_PATH = ROOT / "admin-web" / "static" / "app.js"


class BotFeatureTests(unittest.TestCase):
    def test_bot_operator_interface_is_russian_only(self):
        bot = BOT_PATH.read_text(encoding="utf-8")
        i18n = (ROOT / "gotelegram-bot" / "i18n.py").read_text(encoding="utf-8")
        self.assertNotIn('callback_data="menu_lang"', bot)
        self.assertNotIn('callback_data="lang_set_', bot)
        self.assertNotIn('CommandHandler("lang"', bot)
        self.assertIn('SUPPORTED_LANGS = ("ru",)', i18n)
        self.assertIn('return "ru"', i18n)
        self.assertNotIn('_load_lang_file("en")', i18n)

        lang_dir = ROOT / "gotelegram-bot" / "lang"
        english = json.loads((lang_dir / "en.json").read_text(encoding="utf-8"))
        russian = json.loads((lang_dir / "ru.json").read_text(encoding="utf-8"))
        self.assertEqual(set(russian), set(english))

    def test_operator_interfaces_do_not_contain_promotional_links(self):
        sources = [
            BOT_PATH.read_text(encoding="utf-8"),
            INSTALL_PATH.read_text(encoding="utf-8"),
            ADMIN_INDEX_PATH.read_text(encoding="utf-8"),
            ADMIN_JS_PATH.read_text(encoding="utf-8"),
        ]
        combined = "\n".join(sources)

        self.assertNotIn("vk.cc/ct29NQ", combined)
        self.assertNotIn("vk.cc/cUxAhj", combined)
        self.assertNotIn("cloudtips.ru", combined)
        self.assertNotIn("menu_promo", combined)
        self.assertNotIn("promoModal", combined)

    def test_bot_menu_excludes_destructive_remote_operations(self):
        source = BOT_PATH.read_text(encoding="utf-8")
        menu_body = re.search(
            r"def get_main_menu\(.*?(?=\n\n(?:async )?def |\n\n#)",
            source,
            flags=re.S,
        )
        self.assertIsNotNone(menu_body)

        body = menu_body.group(0)
        for callback in (
            "menu_install",
            "menu_restore",
            "menu_update",
            "menu_change",
            "menu_website",
            "menu_remove",
        ):
            self.assertNotIn(f'callback_data="{callback}"', body)

    def test_catalog_contains_template_ids_that_break_raw_callback_data(self):
        catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        raw_lengths = [
            len(f"pro_tpl_{tpl['id']}".encode("utf-8"))
            for cat in catalog.get("categories", [])
            for tpl in cat.get("templates", [])
        ]

        self.assertTrue(any(length > 64 for length in raw_lengths))

    def test_bot_uses_short_template_callback_keys(self):
        source = BOT_PATH.read_text(encoding="utf-8")

        self.assertNotIn("callback_data=f\"pro_tpl_{tpl['id']}\"", source)
        self.assertNotIn('callback_data=f"pro_confirm_{tpl_id}"', source)
        self.assertIn("pro_template_map", source)
        self.assertIn("resolve_pro_template_id", source)

    def test_template_callbacks_are_restart_safe_hashes(self):
        source = BOT_PATH.read_text(encoding="utf-8")
        category_body = re.search(
            r"async def cb_pro_category\(.*?(?=\n\n(?:async )?def |\n\n#)",
            source,
            flags=re.S,
        )
        resolve_body = re.search(
            r"def resolve_pro_template_id\(.*?(?=\n\n(?:async )?def |\n\n#)",
            source,
            flags=re.S,
        )
        self.assertIsNotNone(category_body)
        self.assertIsNotNone(resolve_body)

        self.assertIn('pro_template_key_for_id(context, tpl["id"])', category_body.group(0))
        self.assertNotIn("enumerate(templates)", category_body.group(0))
        self.assertNotIn("mapping.clear()", category_body.group(0))
        self.assertIn("load_json(TEMPLATES_CATALOG)", resolve_body.group(0))
        self.assertIn("hashlib.sha1", resolve_body.group(0))

    def test_telemt_version_checks_systemd_path_fallbacks(self):
        source = BOT_PATH.read_text(encoding="utf-8")
        version_body = re.search(
            r"async def get_telemt_version\(\).*?(?=\n\n(?:async )?def |\n\n#)",
            source,
            flags=re.S,
        )
        self.assertIsNotNone(version_body)
        body = version_body.group(0)

        self.assertIn('"--version"', body)
        self.assertIn('"-V"', body)
        self.assertIn('"/usr/local/bin/telemt"', body)
        self.assertIn("for command in", body)
        self.assertIn("for args in", body)
        self.assertNotIn('"-v"', body)

    def test_telemt_update_menu_reuses_version_helper(self):
        source = BOT_PATH.read_text(encoding="utf-8")
        update_body = re.search(
            r"async def cb_menu_update\(.*?(?=\n\n(?:async )?def |\n\n#)",
            source,
            flags=re.S,
        )
        self.assertIsNotNone(update_body)
        body = update_body.group(0)

        self.assertIn("await get_telemt_version()", body)
        self.assertNotIn('sh("telemt", "--version")', body)

    def test_bot_update_helper_exists_but_menu_start_does_not_mutate_services(self):
        source = INSTALL_PATH.read_text(encoding="utf-8")
        auto_body = re.search(
            r"auto_update_bot_if_possible\(\).*?(?=\n\n[A-Za-z0-9_]+\(\) |\n\n#)",
            source,
            flags=re.S,
        )
        self.assertIsNotNone(auto_body)

        auto_text = auto_body.group(0)
        self.assertIn('bot_service_status', auto_text)
        self.assertIn('bot_install', auto_text)
        self.assertIn('cmp -s "$SCRIPT_DIR/gotelegram-bot/bot.py" "$BOT_DIR/bot.py"', auto_text)
        self.assertIn('cmp -s "$SCRIPT_DIR/gotelegram-bot/i18n.py" "$BOT_DIR/i18n.py"', auto_text)
        self.assertIn('cmp -s "$SCRIPT_DIR/gotelegram-bot/requirements.txt" "$BOT_DIR/requirements.txt"', auto_text)

        main_text = source[source.index("\nmain() {"):source.index('\nmain "$@"')]
        self.assertNotIn("auto_migrate_legacy_state || true", main_text)
        self.assertNotIn("auto_update_bot_if_possible || true", main_text)
        self.assertNotIn("auto_install_admin_web_if_possible || true", main_text)


if __name__ == "__main__":
    unittest.main()
