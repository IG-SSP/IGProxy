# Участие в разработке

Спасибо за интерес к IGProxy.

## Перед изменениями

1. Создайте отдельную ветку.
2. Не добавляйте `.env`, токены, proxy-ссылки, серверные конфиги и бэкапы.
3. Сохраняйте совместимость обновления: пользовательские ключи и настройки
   существующей установки нельзя пересоздавать без явного действия оператора.
4. Не занимайте и не перенастраивайте чужие порты автоматически.

## Проверки

Запускайте в Linux:

```bash
bash -n bootstrap.sh install.sh install_gotelegram_bot.sh lib/*.sh
python3 -m unittest discover -s tests -v
python3 -m py_compile cluster/*.py gotelegram-bot/*.py admin-web/server.py
node --check admin-web/static/app.js
python3 tools/build_release.py --output /tmp/igproxy-release.tar.gz
python3 tools/build_portable_installer.py --output /tmp/IGProxy
sha256sum -c /tmp/IGProxy.sha256
git diff --check
```

Pull request должен кратко объяснять причину изменения, влияние на обновление и
результаты проверок.
