# VibePlan

Нативный macOS-таскбоард с минималистичным календарём для небольшой команды.
Несколько человек создают, перетаскивают, выстраивают задачи в общем графике.

> **Статус: Phase 0 — skeleton.** Окно собирается, открывается, виден тёплый
> фон в стиле дизайн-системы. UI календаря, бэк и синк — следующие фазы.

---

## Стек

- **App:** Swift / SwiftUI, macOS 14+ (Sonoma)
- **Сборка:** Makefile + `swiftc` (без Xcode-проекта)
- **Сигнатура:** ad-hoc (`-`) — без Apple Developer Program
- **CI:** GitHub Actions → universal DMG в Releases
- **Backend (planned):** Node 20 + Fastify + Prisma + Postgres + WebSocket
- **Локальное хранилище (planned):** SwiftData
- **Дизайн-референс:** [/home/konstantin/Andrew/platform](../Andrew/platform)

## Структура

```
vibeplan/
├── app/                          ← macOS-приложение
│   ├── Sources/                  ← .swift файлы
│   │   ├── App.swift             ← @main entry point
│   │   ├── MainWindowView.swift  ← заглушка для Phase 0
│   │   └── Theme.swift           ← дизайн-токены (цвета, градиенты)
│   ├── Resources/
│   │   ├── AppIcon-Original.png  ← исходник от ChatGPT (1254×1254 RGB)
│   │   ├── AppIcon-Source.png    ← 1024×1024 RGBA, фон вырезан
│   │   └── process_icon.py       ← скрипт нормализации иконки
│   ├── Info.plist
│   ├── VibePlan.entitlements
│   └── Makefile                  ← swiftc + lipo + create-dmg
├── backend/                      ← (TBD, Phase 2)
├── mockups/
│   └── main.html                 ← HTML-мокап главного экрана
├── .github/workflows/release.yml ← билд DMG по тегу v*.*.*
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## Сборка локально (на Mac)

```bash
cd app

# собрать .app для своей архитектуры (M1/M2 → arm64, Intel → x86_64)
make

# открыть собранный .app
make run

# собрать DMG (universal)
brew install create-dmg fileicon
make dmg ARCH=universal
open build/VibePlan.dmg

# почистить build/
make clean
```

## Релиз через GitHub Actions

Workflow `.github/workflows/release.yml` запускается двумя способами:

**1. Тег с версией → автоматический релиз с DMG.**
```bash
git tag v0.1.0
git push origin v0.1.0
```
Через ~5–8 минут на странице **Releases** появится `VibePlan.dmg`.

**2. Ручной запуск из вкладки Actions** (`workflow_dispatch`) — собирает DMG
как артефакт без публикации релиза. Полезно проверить, что сборка вообще
проходит, до того как ставить «настоящий» тег.

## Первый запуск приложения

macOS заругается, что приложение из неподтверждённого источника
(мы не платим $99/год за Apple Developer).
Правый клик по `VibePlan.app` → **Open** → подтвердить — один раз.

## Перегенерировать иконку

```bash
cd app/Resources
python3 process_icon.py   # требуется pillow: pip install pillow
```

Скрипт берёт `AppIcon-Original.png` (исходник 1254×1254 от ChatGPT),
ресайзит до 1024×1024 и chroma-key-ом вырезает почти-белый фон в прозрачный,
сохраняя мягкую тень под squircle. Результат — `AppIcon-Source.png` (RGBA).

`AppIcon.icns` собирается из `AppIcon-Source.png` Make'ом на сборке и не
коммитится (см. `.gitignore`). Хочешь поменять иконку — клади новый
исходник в `AppIcon-Original.png` и перезапускай скрипт.

## Дальше

- [ ] Phase 1 — UI без бэка: месяц-сетка, side panel дня, drag-and-drop
      (SwiftData локально)
- [ ] Phase 2 — Backend: Fastify + Prisma + Postgres
- [ ] Phase 3 — Auth (email + 6-значный код, Keychain для JWT)
- [ ] Phase 4 — Sync: REST + last-write-wins
- [ ] Phase 5 — Realtime через WebSocket
- [ ] Phase 6 — Polish: иконка, анимации, пустые состояния
