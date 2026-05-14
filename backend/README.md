# VibePlan backend

Node 20 + TypeScript + Fastify + Prisma. SQLite в dev'е, Postgres в проде.
REST-эндпойнты для задач; WebSocket-realtime прилетит в Phase 5.

## Быстрый старт (dev, SQLite, без Docker)

```bash
cd backend
cp .env.example .env

npm install
npx prisma migrate dev --name init   # создаст dev.db с таблицами
npm run dev                          # → http://localhost:4400
```

Проверка:
```bash
curl -s http://localhost:4400/health | jq
```

## REST API

### Публичные
| Метод | Путь                    | Что делает                              |
|-------|-------------------------|------------------------------------------|
| GET   | `/health`               | живой? + версия                          |
| POST  | `/auth/request-code`    | прислать 6-значный код на email          |
| POST  | `/auth/verify`          | поменять `code` → JWT + user             |

### Авторизация (Bearer JWT)
| Метод | Путь                    | Что делает                              |
|-------|-------------------------|------------------------------------------|
| GET   | `/me`                   | текущий пользователь                     |
| PATCH | `/me`                   | поменять имя                             |
| GET   | `/tasks`                | список задач                             |
| GET   | `/tasks/:id`            | одна задача с подзадачами                |
| POST  | `/tasks`                | создать                                  |
| PATCH | `/tasks/:id`            | обновить (любое подмножество полей)      |
| DELETE| `/tasks/:id`            | удалить                                  |

> **Заметка для Phase 3:** на `/tasks/*` пока auth-middleware **не** включён —
> чтобы можно было пилить Phase 4 (синк в Mac-приложении) пошагово. Включим
> когда клиент будет слать токен.

### Админ (роль `admin`)
| Метод | Путь                                      | Что делает                  |
|-------|-------------------------------------------|------------------------------|
| GET   | `/admin/allowed-emails`                   | список белого списка         |
| POST  | `/admin/allowed-emails`                   | добавить email + роль        |
| DELETE| `/admin/allowed-emails/:email`            | убрать из белого списка      |
| GET   | `/admin/users`                            | зарегистрированные юзеры     |

Фильтры на `GET /tasks`:
- `?from=2026-05-01T00:00:00Z&to=2026-05-31T23:59:59Z` — диапазон по `startDate`
- `?inbox=true` — только из «Неразобранного»
- `?inbox=false` — только из календаря

## Поток авторизации

```
       POST /auth/request-code { email }                       ┌─── допущен? ───┐
client ─────────────────────────────────────────────► backend ─┤                │
                                                               │   NO → 200 ok  │ (silently)
                                                               │   YES          │
                                                               ▼                │
                                                       send 6-digit code        │
                                                  (Resend if RESEND_API_KEY,    │
                                                   иначе в server.log)          │
       POST /auth/verify { email, code }                                        │
client ─────────────────────────────────────────────► backend ──► upsert User,  │
                                                                  выдать JWT     │
       { token, user }                                                          │
client ◄────────────────────────────────────────────────────────────────────────┘
```

Параметры по умолчанию: код действует **10 минут**, максимум **5 попыток** на код,
дальше нужен новый. JWT живёт **30 дней** (`JWT_TTL` в `.env`).

## Bootstrap admin

При первом запуске, если белый список пустой, в него автоматом добавляется
`BOOTSTRAP_ADMIN_EMAIL` из `.env` (по умолчанию `kos2cherdan@gmail.com`) с ролью `admin`.
Если хотя бы один admin уже есть — bootstrap скипается. Это позволяет
залогиниться с самого начала без out-of-band setup'а.

### Создание задачи

```bash
curl -X POST http://localhost:4400/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Демо запись",
    "note": "Записать как работает sync",
    "startDate": "2026-05-15T14:00:00.000Z",
    "durationMinutes": 90,
    "category": "urgent",
    "status": "open",
    "subtasks": [
      { "title": "Подготовить тезисы", "done": false, "order": 0 },
      { "title": "Записать видео",     "done": false, "order": 1 }
    ]
  }' | jq
```

### Поля задачи

```ts
interface Task {
  id:              string;             // cuid (бэкенд) или клиентский UUID
  title:           string;
  note:            string;
  startDate:       string;             // ISO 8601, UTC
  durationMinutes: number;             // 1..1440
  category:        "personal" | "work" | "urgent" | "ideas" | "learning";
  status:          "open" | "inProgress" | "done";
  sortOrder:       number;
  inInbox:         boolean;
  createdAt:       string;             // ISO 8601
  updatedAt:       string;             // ISO 8601
  subtasks:        Subtask[];
}

interface Subtask {
  id:    string;
  title: string;
  done:  boolean;
  order: number;
}
```

## Прод (Postgres + Docker)

```bash
cd backend
docker compose up -d --build
docker compose logs -f api
```

API на `http://<host>:4400`, Postgres на `:5432`. Volume `vibeplan-db`
переживает рестарты контейнера. Миграции применяются автоматически при
старте api (см. `CMD` в Dockerfile).

Для прода через nginx/Caddy с TLS — стандартный reverse-proxy на `:4400`.

## Переключение SQLite → Postgres

1. В `.env` раскомментировать `DATABASE_URL=postgresql://…`
2. В `prisma/schema.prisma` сменить `provider = "sqlite"` → `"postgresql"`
3. `npx prisma migrate deploy` (или `migrate dev` если первая инсталляция)

## Структура

```
backend/
├── src/
│   ├── index.ts         ← bootstrap (listen + graceful shutdown)
│   ├── server.ts        ← Fastify factory (cors, sensible, routes)
│   ├── db.ts            ← PrismaClient singleton
│   ├── schemas.ts       ← zod схемы запросов
│   └── routes/
│       ├── health.ts
│       └── tasks.ts
├── prisma/
│   └── schema.prisma
├── Dockerfile           ← multi-stage build, prod image
├── docker-compose.yml   ← Postgres + api
└── .env.example
```

## Что НЕ реализовано (по фазам)

- **Phase 3.x** — assignees у задачи (M:N user↔task), `Task.creatorId` уже есть
- **Phase 4** — клиент-сторона: Mac-приложение шлёт токен, синкается с бэком
- **Phase 5** — WebSocket realtime (плагин `@fastify/websocket` рядом с REST)
- **Phase 6** — rate-limit на `/auth/request-code`, метрики, sentry
