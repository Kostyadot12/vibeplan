import Foundation
import SwiftData

enum Seed {
    static func populate(into ctx: ModelContext) {
        let cal = CalendarUtil.ru
        let today = CalendarUtil.startOfDay(.now)

        func at(_ dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
            let day = cal.date(byAdding: .day, value: dayOffset, to: today) ?? today
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            return cal.date(from: comps) ?? day
        }

        let standup = PlanTask(
            title: "Stand-up команды",
            note: "Что вчера / что сегодня / блокеры.",
            startDate: at(0, hour: 9),
            durationMinutes: 30,
            category: .work,
            status: .done,
            sortOrder: 0
        )

        let demo = PlanTask(
            title: "Demo сборки VibePlan через GitHub Actions",
            note: "Показать первый DMG и пройтись по workflow.",
            startDate: at(0, hour: 14),
            durationMinutes: 90,
            category: .urgent,
            status: .inProgress,
            sortOrder: 1
        )
        demo.subtasks = [
            Subtask(title: "Создать workflow release.yml", done: true, order: 0),
            Subtask(title: "Поставить тег v0.1.0",        done: true, order: 1),
            Subtask(title: "Скачать DMG, проверить запуск", done: false, order: 2),
            Subtask(title: "Записать видео-инструкцию",   done: false, order: 3)
        ]

        let course = PlanTask(
            title: "Курс SwiftUI: модуль 3 — Drag & Drop",
            startDate: at(0, hour: 16),
            durationMinutes: 60,
            category: .learning,
            status: .open,
            sortOrder: 2
        )

        let training = PlanTask(
            title: "Тренировка",
            startDate: at(0, hour: 18),
            durationMinutes: 60,
            category: .personal,
            status: .open,
            sortOrder: 3
        )

        let ideas = PlanTask(
            title: "Идея сценария для канала",
            note: "Накидать черновик про вайбкодинг и архитекторов",
            startDate: at(0, hour: 11),
            durationMinutes: 60,
            category: .ideas,
            status: .inProgress,
            sortOrder: 4
        )

        let tomorrowCall = PlanTask(
            title: "Звонок с Костей",
            startDate: at(1, hour: 10),
            durationMinutes: 30,
            category: .work,
            status: .open,
            sortOrder: 0
        )

        let reading = PlanTask(
            title: "Чтение",
            startDate: at(1, hour: 20),
            durationMinutes: 45,
            category: .learning,
            status: .open,
            sortOrder: 1
        )

        let release = PlanTask(
            title: "Релиз v1.0",
            startDate: at(7, hour: 12),
            durationMinutes: 60,
            category: .urgent,
            status: .open,
            sortOrder: 0
        )

        for t in [standup, demo, course, training, ideas, tomorrowCall, reading, release] {
            ctx.insert(t)
        }
        try? ctx.save()
    }
}
