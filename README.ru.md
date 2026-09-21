# XrayBar

[English](README.md) · **Русский**

Небольшое нативное приложение для строки меню macOS, которое запускает
[Xray-core](https://github.com/XTLS/Xray-core) с его **нативным TUN**: весь трафик с
маршрутизацией по geosite/geoip идёт через один процесс, без посредников.

> Статус: ранний. Этап 1 (подключение из меню) работает, см. [docs/ru/ROADMAP.md](docs/ru/ROADMAP.md).

## Зачем

Клиенты Xray для macOS обычно либо комбайны из нескольких ядер, либо выглядят совсем
не как приложения для Mac, либо и то и другое. XrayBar делает одну вещь и старается делать
её так, как сделала бы Apple: меню как у Wi-Fi, запрос пароля, когда нужен root, и ничего
не остаётся после отключения. См. [docs/ru/PRINCIPLES.md](docs/ru/PRINCIPLES.md).

## Сборка и запуск

Нужно: macOS 15+, Command Line Tools (`xcode-select --install`). Xcode не нужен.

```sh
scripts/make-app.sh                          # собирает build/XrayBar.app (ad-hoc подпись)
cp -R build/XrayBar.app /Applications/       # и запускайте из /Applications
```

Для разработки подойдёт и `swift run`.

**Xray Version ›** скачивает релиз Xray, проверенный с XrayBar, или любой более новый; версии
хранятся рядом, а первое подключение с новой версией проверяется, и если трафик не проходит,
вернуться на прежнюю можно в одно нажатие. **Update Routing Data** обновляет
`geoip.dat`/`geosite.dat`. Всё сверяется по контрольным суммам. До этого используется установка
v2rayN (`~/Library/Application Support/v2rayN/bin`). Серверы
импортируются через **Import Link or QR Code from Clipboard** (скопируйте ссылку `vless://…` или нажмите ⌘⇧⌃4 и
выделите QR-код — снимок попадёт в буфер обмена) или **Import from v2rayN…** (только чтение). **Share Server…** показывает QR-код. Удерживайте **Option** при открытом меню, чтобы удалить сервер или набор правил, скопировать
ссылку на сервер или увидеть технические подробности под строкой статуса. С **Connect at Launch** (включено по умолчанию)
XrayBar при запуске подключается к последнему серверу; вместе с **Open at Login** ничего
нажимать не нужно.

При подключении запрашивается пароль администратора: для создания TUN-интерфейса нужен root.
**Use Touch ID to Connect…** один раз устанавливает небольшой помощник, принадлежащий root;
после этого каждый Connect спрашивает Touch ID (или пароль) в системном окне. Под root
выполняется только короткий читаемый код:
[`Sources/XrayBar/Resources/xraybar-session.sh`](Sources/XrayBar/Resources/xraybar-session.sh).

## Можно ли ему доверять?

Верить на слово не нужно. Приложение — это около 1400 строк Swift в нескольких пронумерованных файлах, которые
читаются по порядку, плюс около 200 строк root-скриптов и необязательный root-помощник
примерно на 110 строк, без зависимостей.

- [docs/ru/SECURITY.md](docs/ru/SECURITY.md) — что делает приложение, модель угроз, известные ограничения.
- `scripts/audit.sh` — детерминированная опись: привилегии, процессы, сеть, запись файлов.
- [docs/ru/AUDIT.md](docs/ru/AUDIT.md) — чек-лист проверки, пригодный как инструкция для ИИ-модели.

## Тесты

```sh
scripts/test.sh                 # модульные тесты
scripts/test.sh --integration   # плюс прогон конфигов из вашего v2rayN через xray (только чтение)
```

## Лицензия и благодарности

MIT, см. [LICENSE](LICENSE). Поведение и форматы повторяют
[v2rayN](https://github.com/2dust/v2rayN) (код v2rayN не используется). Xray-core — отдельная
программа под MPL-2.0. Данные маршрутизации:
[runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat),
[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat).
