# Changelog

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
