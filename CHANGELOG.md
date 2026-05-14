# Changelog

## 0.5.2 — fix HTTP backend access + redesigned login

- **Fix:** `NSAppTransportSecurity → NSAllowsArbitraryLoads = true` в Info.plist.
  Без него macOS 14+ блокирует `http://` и логин падал с
  «The resource could not be loaded because the App Transport Security policy
  requires the use of a secure connection.»
  Когда переедешь на TLS — можно снять.
- **Redesign LoginView:**
  - Тёплый градиентный фон с двумя цветными blob'ами (фиолет + синий)
    в углах для глубины
  - Большой брендовый логотип с мини-сеткой календаря (повторяет AppIcon)
    и градиентом-чёрный → тёмно-фиолетовый
  - Чистая белая карточка (вместо кашеобразного `.ultraThinMaterial`)
    с двойной тенью для воздуха
  - Поля с иконками и подсветкой фокуса (1.5pt чёрный border)
  - Auto-submit когда введены все 6 цифр кода
  - Анимация появления поля кода
  - Счётчик «N/6» рядом с заголовком кода
  - Капсула-кнопка с градиентным фоном и сильной тенью
  - Server-чип с зелёной точкой и аккуратной тенью

## 0.5.1 — fix v0.5.0 build + production polish

- **Fix:** `App.init` no longer wraps RealtimeClient/TeamRoster construction in
  `MainActor.assumeIsolated { ... }` — that closure was capturing `self.auth`
  before the `_auth` State backing was assigned, breaking the build.
  RealtimeClient and TeamRoster are now `@Observable` (not `@MainActor`-class)
  with `@MainActor` only on the methods/properties that touch UI state.
- Empty states in DayPanelView: «Свободный день» when no tasks for selected
  day, «Ничего не найдено» when the search filter wipes everything out.
- Keyboard shortcuts: ⌘N — новая задача · ⌘T — сегодня · ⌘R — синк сейчас
- `.task` and `Task { ... }` blocks marked explicitly `@MainActor` to avoid
  inherited-isolation surprises across Swift toolchains.

## 0.5.0 — Phase 4.x + 5 + 6 + Polish

### 4.x — security cleanup
- `/tasks/*` теперь требует JWT (раньше был открыт для разработки Phase 4)

### 5 — WebSocket realtime
- Backend: `@fastify/websocket`, endpoint `/ws?token=…&clientId=…`
  - JWT-аутентификация, heartbeat ping каждые 25 сек
  - На `POST/PATCH/DELETE /tasks` сервер броадкастит событие всем
    подключённым клиентам с `originClientId` (для echo prevention)
  - События: `task.created` / `task.updated` / `task.deleted` / `hello` / `ping`
- Backend: `X-Client-Id` header на REST → попадает в broadcast как `originClientId`
- App: `RealtimeClient` (URLSessionWebSocketTask + автореконнект 1→2→4→8→16→30s)
  - Применяет входящие события к SwiftData
  - Игнорирует свои события по совпадению `clientId` (UUID per installation, в UserDefaults)
  - Запускается на логине, останавливается на logout

### 6 — Multi-assignees
- Backend: `TaskAssignee` join model (Task ↔ User), миграция
- Backend: `assigneeIds[]` в POST/PATCH `/tasks`, `assignees[]` в ответе
- Backend: `GET /team` — список всех юзеров (для picker'а)
- App: `TaskAssignee` @Model + `PlanTask.assignees` relationship
- App: `TeamRoster` (Observable, кэширует /team на логине)
- App: assignee-picker в редакторе — chip-row с `AvatarBadge` + чекмарком
- App: AvatarStack на карточке задачи (до 3 + "+N")
- App: переиспользуемый `AvatarBadge` со стабильной палитрой по email-хешу
- App: `FlowLayout` — кастомный SwiftUI Layout для wrap'а chip-рядов

### Polish
- Рабочий поиск в тулбаре (`TextField` + `xmark.circle` для очистки)
  - Фильтрует month grid, day timeline, inbox по title/note/assignee
- Live-индикатор в тулбаре: 🟢 Live · 🟠 Подключение · ⚪ Offline
- Аватары в стопке на карточках задач (mockup parity)

### Backend deployment
- Прод-билд (`npm run build` → `dist/`) + перезапуск systemd-сервиса
- Хостится на `82.38.68.48:4400` (этот сервер)

## 0.4.0 — Phase 4: Mac-приложение умеет логиниться и синкаться

- LoginView: email → код из письма → JWT в Keychain
- AppSettings (UserDefaults): backend URL по умолчанию `http://82.38.68.48:4400`
- SettingsSheet: аккаунт, сервер с проверкой, статус синка, кнопка «Выйти»
- APIClient на URLSession + ISO8601-даты + Bearer-токен
- DTOs (Codable) под backend контракт `/auth/*`, `/me`, `/tasks`
- SyncEngine (Observable):
  - **На логин:** push локальных без `serverId` → pull всех → reconcile
  - **На каждую мутацию:** best-effort push (не блокирует UI)
  - **Удаление:** DELETE на бэке если есть `serverId`, иначе только локально
- В тулбаре: User badge (инициалы), индикатор синка, settings cog
- Schema: `PlanTask.serverId`, `Subtask.serverId` (lightweight migration)
- Один сервис на инсталляцию, один аккаунт; разлогин не трогает локальные данные

## Phase 3 — Auth на бэкенде

- Prisma модели: `User`, `AllowedEmail`, `VerificationCode`
- `Task.creatorId` (nullable) → `User` для будущих фильтров «мои задачи»
- `@fastify/jwt` плагин, JWT с TTL 30 дней, секрет из `JWT_SECRET`
- `POST /auth/request-code { email }` — генерирует 6-значный код, кладёт SHA-256
  в БД, шлёт через Resend (если есть `RESEND_API_KEY`) или в `server.log`.
  Не-whitelisted email отвечает `200 ok` без отправки (no oracle)
- `POST /auth/verify { email, code }` — проверка через SHA-256, max 5 попыток,
  10 мин TTL, upsert `User`, выдача JWT
- `GET/PATCH /me` — текущий пользователь
- `GET/POST/DELETE /admin/allowed-emails` — управление белым списком (роль `admin`)
- `GET /admin/users` — список зарегистрированных
- Bootstrap: при первом старте `BOOTSTRAP_ADMIN_EMAIL` (default `kos2cherdan@gmail.com`)
  попадает в whitelist как admin, если он пустой
- Бэкенд развёрнут как systemd-user service на этой машине: `82.38.68.48:4400`

## Phase 2 — Backend (без выхода DMG, only `backend/`)

- Node 20 + TypeScript + Fastify + Prisma + SQLite (dev) / Postgres (prod)
- REST: `GET/POST/PATCH/DELETE /tasks`, `GET /tasks/:id`, `GET /health`
- Schema-validation через zod (категории + статусы фиксированные enum-ы)
- Поля Task: id, title, note, startDate, durationMinutes, category, status,
  sortOrder, inInbox, createdAt, updatedAt, subtasks[] — 1:1 со SwiftData
- Subtasks обновляются replace-all семантикой
- Фильтры по диапазону дат (`from`/`to`) и Inbox (`inbox=true|false`)
- Dockerfile (multi-stage) + docker-compose с Postgres healthcheck
- Порт 4400 (4000 занят бэком /Andrew/platform на этой машине)
- End-to-end smoke-tested локально (curl POST → GET → PATCH → DELETE → 0)

Auth/User/WebSocket — следующие фазы. Это чистый CRUD-фундамент.

## 0.3.0 — Phase 1.x: drag-and-drop + Inbox + переписанный редактор

- Перетаскивание задач между днями в месяц-сетке (время сохраняется)
- Папка «Неразобранное» под календарём — раскрываемая, со счётчиком
- Drop-зона у Inbox с подсветкой при drag-over
- Перенос задачи Inbox → день (получает 09:00 как стартовое время)
- Перенос день → Inbox (задача исчезает из календаря)
- Свежие seed-данные включают 3 примера задач в Inbox
- Schema migration: новое поле `PlanTask.inInbox: Bool = false`
- Контекстное меню Inbox-строки: редактировать / удалить

### Редактор задачи переписан

- Дата + время — chip-кнопка с popover'ом (графический календарь внутри)
- Длительность — ряд chip-пресетов: 15м / 30м / 45м / 1ч / 1.5ч / 2ч / 3ч / 4ч
- Категория — цветные chip'ы вместо стандартного NSPopUpButton
- Статус — три chip'а с глифами (○ / ◐ / ●)
- Заметка — frosted-glass область с прозрачным placeholder'ом
- Подзадачи — кастомные строки с hover-кнопкой удаления, счётчик «N/M»
- Шапка с цветной иконкой по текущей категории
- Footer: Удалить (red ghost), Отмена, Сохранить (чёрная капсула с тенью)
- Автофокус на title при создании новой задачи

## 0.2.0 — Phase 1: рабочий календарь и редактор задач

- SwiftData models: `PlanTask`, `Subtask`, `PlanCategory`, `PlanStatus`
- Месяц-сетка 6 недель с пилюлями задач (цвет = категория, +N если больше 3)
- Боковая панель дня — таймлайн 07:00–22:00 с карточками-эвентами
- Карточка задачи: чекбокс статуса (3 состояния), время + длительность,
  заметка, чеклист подзадач, цветовая категория, контекстное меню (delete)
- Лист «Новая задача / Редактировать»: title, дата, время, длительность,
  категория, статус, заметка, добавление/удаление подзадач, чекбоксы
- Тулбар: переключатель «Личные/Командные» (косметика до Phase 3),
  кнопки «Сегодня» и «+ Задача»
- Авто-сид примерных задач при первом запуске (пустая база)
- Русская локализация календаря, неделя с понедельника

## 0.1.0 — Phase 0 skeleton

- Native macOS app skeleton (SwiftUI, macOS 14+)
- Ad-hoc signed universal build (Apple Silicon + Intel) via Makefile
- GitHub Actions release pipeline producing `VibePlan.dmg`
- App icon (squircle с календарём и task-полосками, 1024×1024 RGBA)
  → ICNS via `sips` + `iconutil` at build time
- Design tokens scaffolded in `Theme.swift` (ink palette, category colors,
  background gradient) to match the platform mockup
