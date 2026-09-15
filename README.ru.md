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

Нужно: macOS 14+, Command Line Tools (`xcode-select --install`). Xcode не нужен.

```sh
swift build -c release
.build/release/XrayBar
```

На этапе 1 бинарь `xray` и файлы `geoip.dat`/`geosite.dat` берутся из существующей установки
(по умолчанию из `~/Library/Application Support/v2rayN/bin` от v2rayN). Серверы
импортируются через **Import Link from Clipboard** (`vless://…`) или
**Import from v2rayN…** (только чтение).

При подключении запрашивается пароль администратора: для создания TUN-интерфейса нужен root.
Под root выполняется только один короткий читаемый скрипт:
[`Sources/XrayBar/Resources/xraybar-session.sh`](Sources/XrayBar/Resources/xraybar-session.sh).

## Можно ли ему доверять?

Верить на слово не нужно. Приложение — это около 600 строк Swift в шести файлах, которые
читаются по порядку, плюс root-скрипт примерно на 100 строк, без зависимостей.

- [docs/ru/SECURITY.md](docs/ru/SECURITY.md) — что делает приложение, модель угроз, известные ограничения.
- `scripts/audit.sh` — детерминированная опись: привилегии, процессы, сеть, запись файлов.
- [docs/ru/AUDIT.md](docs/ru/AUDIT.md) — чек-лист проверки, пригодный как инструкция для ИИ-модели.

## Тесты

```sh
swift test
# на ваших локальных данных v2rayN и бинаре xray (только чтение):
swift build --build-tests && XRAYBAR_INTEGRATION=1 swift test --skip-build
```

## Лицензия и благодарности

MIT, см. [LICENSE](LICENSE). Поведение и форматы повторяют
[v2rayN](https://github.com/2dust/v2rayN) (код v2rayN не используется). Xray-core — отдельная
программа под MPL-2.0. Данные маршрутизации:
[runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat),
[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat).
