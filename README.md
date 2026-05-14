# VibePlan

Нативный macOS-таскбоард с минималистичным календарём для небольшой команды.
Несколько человек создают, перетаскивают, выстраивают задачи в общем графике.

> **Статус: Phase 1.x — локальный календарь с drag-and-drop.** Месяц-сетка,
> таймлайн дня, CRUD, чеклисты, категории, статусы, перетаскивание задач
> между днями и в «Неразобранное». Данные — локально в SwiftData.
> Бэк, синк и команда — следующие фазы.

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
│   │   ├── App.swift             ← @main + ModelContainer + одноразовый seed
│   │   ├── Model.swift           ← SwiftData @Model: PlanTask, Subtask, Category, Status
│   │   ├── Seed.swift            ← начальные данные на первый запуск
│   │   ├── DragState.swift       ← shared Observable для drag-сессии
│   │   ├── MainWindowView.swift  ← layout: тулбар + грид + Inbox + side panel
│   │   ├── MonthGridView.swift   ← месяц-сетка 7×6, drop-target по дню
│   │   ├── DayPanelView.swift    ← таймлайн дня + draggable карточки
│   │   ├── InboxBar.swift        ← «Неразобранное» (раскрывается, drop-target)
│   │   ├── TaskEditorSheet.swift ← модалка «Новая / Редактировать»
│   │   └── Theme.swift           ← дизайн-токены
│   ├── Resources/
│   │   ├── AppIcon-Original.png  ← исходник от ChatGPT (1254×1254 RGB)
│   │   ├── AppIcon-Source.png    ← 1024×1024 RGBA, фон вырезан
│   │   └── process_icon.py       ← скрипт нормализации иконки
│   ├── Info.plist
│   ├── VibePlan.entitlements
│   └── Makefile                  ← swiftc + lipo + create-dmg
├── backend/                      ← Node + Fastify + Prisma (Phase 2)
│   ├── src/                      ← server, routes, schemas
│   ├── prisma/                   ← schema + миграции
│   ├── Dockerfile + docker-compose.yml
│   └── README.md
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

- [x] **Phase 0** — Скелет + GitHub Actions (v0.1.0)
- [x] **Phase 1** — Месяц-сетка + таймлайн + редактор + SwiftData (v0.2.0)
- [x] **Phase 1.x** — Drag&drop между днями + «Неразобранное» (v0.3.0)
- [x] **Phase 2** — Backend: Fastify + Prisma + SQLite/Postgres, REST CRUD
- [x] **Phase 3** — Auth на бэке: email + 6-значный код, JWT, whitelist, admin-API
- [x] **Phase 4** — Mac-клиент: login UI, Keychain, APIClient, SyncEngine (v0.4.0)
- [ ] **Phase 5** — WebSocket realtime (вместо polling-style sync)
- [ ] **Phase 6** — Many-to-many assignees, polish, dark mode
- [ ] **Phase 3** — Auth (email + 6-значный код, Keychain для JWT)
- [ ] **Phase 4** — Sync: REST + last-write-wins
- [ ] **Phase 5** — Realtime через WebSocket
- [ ] **Phase 6** — Polish: анимации, пустые состояния, dark mode
