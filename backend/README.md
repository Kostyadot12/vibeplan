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

| Метод | Путь                    | Что делает                              |
|-------|-------------------------|------------------------------------------|
| GET   | `/health`               | живой? + версия                          |
| GET   | `/tasks`                | список задач                             |
| GET   | `/tasks/:id`            | одна задача с подзадачами                |
| POST  | `/tasks`                | создать                                  |
| PATCH | `/tasks/:id`            | обновить (любое подмножество полей)      |
| DELETE| `/tasks/:id`            | удалить                                  |

Фильтры на `GET /tasks`:
- `?from=2026-05-01T00:00:00Z&to=2026-05-31T23:59:59Z` — диапазон по `startDate`
- `?inbox=true` — только из «Неразобранного»
- `?inbox=false` — только из календаря

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

- **Phase 3** — auth: email + 6-значный код, JWT, белый список email
- **Phase 3** — модель `User` / `Team`, owner/assignee у задачи
- **Phase 5** — WebSocket realtime
- **Phase 6** — Resend для отправки кодов, rate-limit, метрики
