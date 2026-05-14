# Changelog

## 0.7.0 — Файлы, комментарии, метки, напоминания, активность

Большая итерация — продакшн-функционал командного таскера.

### Файловые вложения
- Backend: `Attachment` модель, multipart-upload через `@fastify/multipart`,
  static-доступ через `/uploads/attachments/...`. Любой тип, до 10 МБ
- App: секция «Файлы» в редакторе, кнопка «Добавить файл» (NSOpenPanel),
  иконки по типу (PDF/изображения/таблицы/Word/архивы), скачивание/удаление
- Прогноз размера в строке файла (КБ/МБ)

### Комментарии на задачах
- Backend: `Comment` модель + `POST/GET/DELETE /tasks/:id/comments`,
  WS-broadcast `comment.created/deleted` всем members'ам
- App: thread в редакторе с аватарами авторов, дата, удаление своих
- Реалтайм: чужие комменты прилетают сразу

### Метки (Tags) — гибкая M:N
- Backend: `Tag` модель (color из палитры категорий), scope = space/personal,
  `TaskTag` join, CRUD-роуты + WS события
- App: chip-row в редакторе, «+» для создания новой метки прямо из редактора
- TagsRoster (@Observable) кэширует, обновляется по WS

### Напоминания (Reminders)
- Backend: `Task.reminderMinutes: Int?` (минуты до start)
- App: chip-ряд «не нужно / 5 / 15 / 30 / 1ч / 2ч / сутки» в редакторе
- Локальное планирование через `UNCalendarNotificationTrigger` (`Notifier`)
- `ReminderScheduler.rescheduleAll` после fullSync и каждого save

### Лента активности
- Backend: `ActivityEvent` модель, append-only лог (task.created,
  comment.created), скоупится по space membership
- App: bell-кнопка в тулбаре → ActivityFeedSheet с аватарами actor'ов

### Keyboard shortcuts
- ⌘1 — переключиться на «Личные»
- ⌘2/⌘3/⌘4… — переключение между пространствами по порядку

### Что отложено в v0.8
- Recurring tasks (повторяющиеся) — нужен правильный RRULE/cron-движок
- Drag time slot в таймлайне — нужна аккуратная gesture-работа
- Голосовой ассистент — отдельный Phase 8 (микрофон + LLM пайплайн)

## 0.6.0 — Профили + видимый автор + inline-edit + системные уведомления

### Backend
- `User.avatarUrl: String?` + multipart-загрузка через `@fastify/multipart`
- Статика `/uploads/*` через `@fastify/static`
- `POST /me/avatar` принимает PNG/JPG/GIF/WEBP до 10 МБ
- `PATCH /me` теперь принимает `name` и `avatarUrl` (можно очистить null'ом)
- `GET /team`, `GET /admin/users`, ассайны и spaceMember'ы возвращают `avatarUrl`

### App — социальные фичи
- **Автор задачи виден** на карточке: маленький аватар в правом-верхнем углу.
  Клик → ProfileSheet с инфой об авторе, hover → tooltip «Создал: …»
- **Профиль (ProfileSheet)**: имя редактируется, аватар загружается через
  NSOpenPanel (PNG/JPG/GIF/WEBP). «Убрать фото» одной кнопкой
- **Аватары везде** реальные если загружены (AsyncImage), fallback —
  инициалы на стабильном градиенте по email
- **Inline-редактирование заголовка**: двойной клик по title в карточке →
  TextField; ⏎ сохраняет, Esc отменяет. Контекст-меню → «Переименовать»
- **macOS-уведомления (UserNotifications)**:
  - Запрос permission при первом запуске
  - При WS-событии `task.created` где ты в assignees → системное уведомление
  - При `task.updated` со статусом done и ты ассайн → уведомление о завершении

### UX полировка
- **Убрали показ адреса сервера** из UI:
  - С экрана логина — server-чип удалён
  - Из настроек — раздел «Сервер» убран
  - Дефолтный URL хардкоднут, остаётся в `AppSettings` для тех. правок

## 0.5.5 — fix v0.5.4 build (MainActor isolation)

- `SpacesRoster.persistScope()` теперь явно `@MainActor` — раньше функция
  была nonisolated и читала `@MainActor var scope`, что в Swift 5.10+
  ломает компиляцию: «main actor-isolated property 'scope' can not be
  referenced from a nonisolated context».
- `RealtimeClient.spacesRoster` больше не `weak` — `@Observable` macros не
  всегда корректно работают со weak storage. Жизненный цикл объектов
  совпадает (оба живут пока работает app), retain cycle невозможен.

## 0.5.4 — Spaces (папки/команды) + реальная приватность

Заменили статичный «командный» режим на полноценные **пространства**
(folders / spaces). Теперь у тебя есть «Личные» + сколько угодно общих
папок, в которые можно приглашать людей по email.

### Backend

- Новые модели Prisma:
  - `Space` (id, name, color, ownerId)
  - `SpaceMember` (M:N user ↔ space, role: owner|member)
  - `PendingSpaceInvite` — для пригласов до того как user зарегался
- `Task.spaceId: String?` — NULL = личная (видна только creator), иначе
  принадлежит space (видна всем members)
- Routes:
  - `GET /spaces` — мои пространства
  - `POST /spaces` — создать (я owner)
  - `PATCH /spaces/:id` — переименовать/перекрасить (owner only)
  - `DELETE /spaces/:id` — удалить, задачи становятся личными creator'ов
  - `POST /spaces/:id/members` — пригласить email (auto-whitelist + pending)
  - `DELETE /spaces/:id/members/:userId` — kick (owner) или leave (self)
- `GET /tasks?scope=personal|<spaceId>` — фильтр по scope; без параметра
  возвращает всё что мне видно
- WebSocket scoped broadcast: `task.*` события идут только members'ам space
  (или creator'у для личных). Новые события `space.created/updated/deleted`
- При логине resolve'им `PendingSpaceInvite` → SpaceMember автоматом

### App

- Новые SwiftData модели: `Space`, `SpaceMember`
- `PlanTask.spaceServerId: String?` + `creatorServerId: String?`
- `Scope` enum + `SpacesRoster` (@Observable, восстанавливает scope из
  UserDefaults между запусками)
- Тулбар: вместо переключателя Личные/Командные — Menu со списком
  пространств + «Создать пространство…» + «Настроить…» (для текущего)
- `SpaceSheet`: создание/настройка/приглашение/удаление
- `MonthGrid`/`DayPanel`/`InboxBar` фильтруют задачи по текущему scope
- `TaskEditor`: новые задачи наследуют scope; assignee picker показывает
  только members текущего пространства (в личном scope скрыт)
- `RealtimeClient` обрабатывает `space.*` события — список пространств
  обновляется в реальном времени когда тебя пригласили / выкинули

### UX

- Twin-cap toggle убран — заменён на drop-down пилюлю с иконкой и chevron
- Цвет иконки в дропдауне = цвет выбранного пространства

## 0.5.3 — fix dark-mode invisibility + sweep-pass on text contrast

- **Force `.preferredColorScheme(.light)` на корне** WindowGroup, плюс
  внутри каждого sheet'а (Settings, TaskEditor, Server). Раньше macOS в
  тёмной теме переопределял `.primary` на белый — кнопки «Сегодня»,
  «Проверить», заголовки модалок и текст в полях оказывались
  бело-на-белом и были невидимыми.
- `.tint(VibePlanTheme.ink900)` на корне → системные accent-элементы
  (selection в TextField, и т.п.) тоже подхватывают тёмный.
- Явные `.foregroundStyle` проставлены везде где раньше полагались на
  системный default:
  - Тулбар: «Сегодня», search-TextField, ScopeButton
  - SettingsSheet: заголовок, имя в аккаунте, «Проверить», «Сохранить»,
    «Синк», server-TextField
  - LoginView ServerSheet: «Адрес сервера», все три кнопки, TextField
  - TaskEditorSheet: title-TextField, note-TextEditor, subtask-TextField
- Полупрозрачные `.white.opacity(0.7)` фоны inputs заменены на сплошной
  `Color.white` — крепче читается, не зависит от того что под слоем.
- Background sheet'ов сменён с gradient + .white-overlay на сплошной
  cream `#FAF8F4` — детерминированный, не зависит от вибрансии Material.

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
