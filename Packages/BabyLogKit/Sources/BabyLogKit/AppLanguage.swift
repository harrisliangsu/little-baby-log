import Foundation

/// In-app language. Simplified Chinese is the default. `system` follows the phone.
public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public static let storageKey = "appLanguage"

    public static var storedDefault: AppLanguage { .zhHans }

    public func resolved(preferredIdentifier: String? = Locale.preferredLanguages.first) -> ResolvedLanguage {
        switch self {
        case .zhHans: return .zh
        case .english: return .en
        case .system:
            let id = preferredIdentifier ?? "zh-Hans"
            if id.hasPrefix("zh") { return .zh }
            return .en
        }
    }
}

public enum ResolvedLanguage: String, Codable, Sendable {
    case zh
    case en
}

public enum Copy {
    public static func card(_ card: HomeCard, _ language: ResolvedLanguage) -> String {
        switch (card, language) {
        case (.breast, .zh): return "亲喂"
        case (.breast, .en): return "Nursing"
        case (.formula, .zh): return "奶粉"
        case (.formula, .en): return "Formula"
        case (.wet, .zh): return "小便"
        case (.wet, .en): return "Pee"
        case (.dirty, .zh): return "大便"
        case (.dirty, .en): return "Poop"
        case (.diaperChange, .zh): return "换尿布"
        case (.diaperChange, .en): return "Diaper"
        case (.sleep, .zh): return "睡眠"
        case (.sleep, .en): return "Sleep"
        }
    }

    public static func preference(_ preference: FeedPreference, _ language: ResolvedLanguage) -> String {
        switch (preference, language) {
        case (.breast, .zh): return "母乳"
        case (.breast, .en): return "Breast"
        case (.formula, .zh): return "奶粉"
        case (.formula, .en): return "Formula"
        case (.mixed, .zh): return "混合"
        case (.mixed, .en): return "Both"
        }
    }

    public static func languageName(_ language: AppLanguage, _ resolved: ResolvedLanguage) -> String {
        switch (language, resolved) {
        case (.system, .zh): return "跟随系统"
        case (.system, .en): return "System"
        case (.zhHans, .zh): return "简体中文"
        case (.zhHans, .en): return "Simplified Chinese"
        case (.english, .zh): return "英文"
        case (.english, .en): return "English"
        }
    }

    public static func count(_ n: Int, _ language: ResolvedLanguage) -> String {
        switch language {
        case .zh: return "\(n)次"
        case .en: return n == 1 ? "1 time" : "\(n) times"
        }
    }

    public static func ml(_ value: Double, _ language: ResolvedLanguage) -> String {
        let whole = value.rounded()
        let number = abs(value - whole) < 0.05 ? "\(Int(whole))" : String(format: "%.1f", value)
        switch language {
        case .zh, .en: return "\(number) ml"
        }
    }

    public static func ago(_ date: Date, now: Date = .now, _ language: ResolvedLanguage) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 {
            return language == .zh ? "刚刚" : "Just now"
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return language == .zh ? "\(minutes)分钟前" : (minutes == 1 ? "1 min ago" : "\(minutes) min ago")
        }
        let hours = minutes / 60
        let remain = minutes % 60
        if hours < 24 {
            if language == .zh {
                return remain == 0 ? "\(hours)小时前" : "\(hours)小时\(remain)分前"
            }
            return remain == 0 ? "\(hours)h ago" : "\(hours)h \(remain)m ago"
        }
        let days = hours / 24
        return language == .zh ? "\(days)天前" : (days == 1 ? "1 day ago" : "\(days) days ago")
    }

    public static func duration(_ interval: TimeInterval, _ language: ResolvedLanguage) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        if language == .zh {
            if minutes < 60 { return "\(minutes)分钟" }
            return "\(minutes / 60)小时\(minutes % 60)分"
        }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    public static func none(_ language: ResolvedLanguage) -> String {
        language == .zh ? "还没有" : "None yet"
    }

    public static func noRecords(_ language: ResolvedLanguage) -> String {
        language == .zh ? "还没有记录" : "No records yet"
    }

    public static func today(_ language: ResolvedLanguage) -> String {
        language == .zh ? "今天" : "Today"
    }

    public static func yesterday(_ language: ResolvedLanguage) -> String {
        language == .zh ? "昨天" : "Yesterday"
    }

    public static func last7(_ language: ResolvedLanguage) -> String {
        language == .zh ? "近7天" : "7 days"
    }

    public static func all(_ language: ResolvedLanguage) -> String {
        language == .zh ? "全部" : "All"
    }

    public static func pickDate(_ language: ResolvedLanguage) -> String {
        language == .zh ? "选择日期" : "Pick a date"
    }

    public static func settings(_ language: ResolvedLanguage) -> String {
        language == .zh ? "设置" : "Settings"
    }

    public static func addBaby(_ language: ResolvedLanguage) -> String {
        language == .zh ? "添加宝宝" : "Add a baby"
    }

    public static func iCloud(_ language: ResolvedLanguage) -> String {
        language == .zh ? "iCloud 同步" : "iCloud sync"
    }

    public static func iCloudOn(_ language: ResolvedLanguage) -> String {
        language == .zh ? "已开启" : "On"
    }

    public static func iCloudPaused(_ language: ResolvedLanguage) -> String {
        language == .zh ? "已暂停，记录仍在这台手机" : "Paused. Records stay on this phone"
    }

    public static func retry(_ language: ResolvedLanguage) -> String {
        language == .zh ? "重试" : "Retry"
    }

    public static func languageSection(_ language: ResolvedLanguage) -> String {
        language == .zh ? "语言" : "Language"
    }

    public static func homeCards(_ language: ResolvedLanguage) -> String {
        language == .zh ? "首页卡片" : "Home cards"
    }

    public static func feedStyle(_ language: ResolvedLanguage) -> String {
        language == .zh ? "喂养方式" : "Feeding"
    }

    public static func feedStyleFootnote(_ language: ResolvedLanguage) -> String {
        language == .zh ? "只影响新的首页建议。已有的亲喂或奶粉记录都会保留，也可以再显示出来。" : "This only suggests which cards to show. Existing nursing and formula records stay, and you can show them again."
    }

    public static func reminders(_ language: ResolvedLanguage) -> String {
        language == .zh ? "提醒" : "Reminders"
    }

    public static func on(_ language: ResolvedLanguage) -> String {
        language == .zh ? "开" : "On"
    }

    public static func off(_ language: ResolvedLanguage) -> String {
        language == .zh ? "关" : "Off"
    }

    public static func recent(_ language: ResolvedLanguage) -> String {
        language == .zh ? "最近" : "Last"
    }

    public static func todayWord(_ language: ResolvedLanguage) -> String {
        language == .zh ? "今日" : "Today"
    }

    public static func last24(_ language: ResolvedLanguage) -> String {
        language == .zh ? "24小时" : "24h"
    }

    public static func sleeping(_ language: ResolvedLanguage) -> String {
        language == .zh ? "睡眠中" : "Sleeping"
    }

    public static func anchorStart(_ language: ResolvedLanguage) -> String {
        language == .zh ? "从开始算" : "From the start"
    }

    public static func anchorEnd(_ language: ResolvedLanguage) -> String {
        language == .zh ? "从结束算" : "From the end"
    }

    public static func noBaseline(_ language: ResolvedLanguage) -> String {
        language == .zh ? "还没有可计算的记录。记一笔之后才会提醒。" : "Nothing to count from yet. A reminder starts after you log one."
    }

    public static func waitingForEnd(_ language: ResolvedLanguage) -> String {
        language == .zh ? "这条还没结束，结束后才开始计时。" : "This one is still running. Timing starts when it ends."
    }

    public static func overdue(_ language: ResolvedLanguage) -> String {
        language == .zh ? "预计时间已过。记一笔新的之后会重新计算。" : "That time already passed. A new record schedules the next one."
    }

    public static func acknowledged(_ language: ResolvedLanguage) -> String {
        language == .zh ? "这次已标为完成。下一条新记录之后才会再提醒。" : "Marked done for this one. It waits for a newer record."
    }

    public static func waterFootnote(_ language: ResolvedLanguage) -> String {
        language == .zh
            ? "「喝水」是提醒照护者自己，不是给宝宝的喝水建议，也不是医学意见。"
            : "“Drink water” reminds the caregiver, not the baby. It is not a feeding or medical recommendation."
    }

    public static func widgetLine(_ title: String, _ window: CareRollup.Window, _ language: ResolvedLanguage) -> String {
        switch language {
        case .zh:
            return "\(title) 亲喂\(window.breastCount)次 奶粉\(window.formulaCount)次 \(ml(window.formulaML, language)) 小便\(window.wetCount) 大便\(window.dirtyCount) 换尿布\(window.diaperChangeCount) 睡眠\(window.sleepCount)"
        case .en:
            return "\(title) Nursing \(window.breastCount) Formula \(window.formulaCount) \(ml(window.formulaML, language)) Pee \(window.wetCount) Poop \(window.dirtyCount) Diaper \(window.diaperChangeCount) Sleep \(window.sleepCount)"
        }
    }

    public static func lastFeed(_ language: ResolvedLanguage) -> String {
        language == .zh ? "最近喂奶" : "Last feed"
    }

    public static func lastDiaper(_ language: ResolvedLanguage) -> String {
        language == .zh ? "最近尿布" : "Last diaper"
    }

    public static func lastSleep(_ language: ResolvedLanguage) -> String {
        language == .zh ? "最近睡眠" : "Last sleep"
    }

    public static func deviceReminders(_ language: ResolvedLanguage) -> String {
        language == .zh
            ? "提醒只保存在这台设备上，不会通过 iCloud 同步，所以另一台手机不会跟着响。系统最多大约排 60 条，多个宝宝会轮流占用。"
            : "Reminders stay on this device and are not synced through iCloud, so another phone does not ring too. The system holds about 60 pending alerts, shared across babies."
    }

    public static func sinceLast(_ language: ResolvedLanguage) -> String {
        language == .zh ? "距上次" : "Since last"
    }

    public static func lastAmount(_ language: ResolvedLanguage) -> String {
        language == .zh ? "上次" : "Last"
    }

    public static func tapToLog(_ item: HomeCard, _ language: ResolvedLanguage) -> String {
        language == .zh ? "点按记录\(card(item, language))" : "Tap to log \(card(item, language))"
    }

    public static func widgetLimit(_ hidden: Int, _ size: WidgetSize, _ language: ResolvedLanguage) -> String {
        switch (size, language) {
        case (.small, .zh): return "还有\(hidden)项。小号只显示第1项，换中号或大号。"
        case (.small, .en): return "\(hidden) more. Small shows the first item. Use Medium or Large."
        case (.medium, .zh): return "还有\(hidden)项放不下。换大号，或在编辑小组件里减少。"
        case (.medium, .en): return "\(hidden) more do not fit. Use Large, or remove some in Edit Widget."
        case (.large, .zh): return "还有\(hidden)项放不下。请在编辑小组件里减少项目。"
        case (.large, .en): return "\(hidden) more do not fit. Remove some in Edit Widget."
        }
    }

    public static func missingBaby(_ language: ResolvedLanguage) -> String {
        language == .zh ? "找不到这位宝宝" : "This baby is not on this phone"
    }

    public static func noReminder(_ language: ResolvedLanguage) -> String {
        language == .zh ? "没有已设提醒" : "No reminder set"
    }

    public static func setReminder(_ language: ResolvedLanguage) -> String {
        language == .zh ? "已设提醒" : "Reminder"
    }

    public static func recentRecords(_ language: ResolvedLanguage) -> String {
        language == .zh ? "近期记录" : "Recent"
    }

    public static func pickWidgetItems(_ language: ResolvedLanguage) -> String {
        language == .zh ? "在编辑小组件里选择要显示的项目" : "Choose items in Edit Widget"
    }

    public static func widgetSeparate(_ language: ResolvedLanguage) -> String {
        language == .zh
            ? "桌面小组件在主屏幕上长按后编辑。每个小组件自己选宝宝和项目，不跟着首页顺序变。"
            : "Touch and hold a Home Screen widget to edit it. Each widget keeps its own baby and items, separate from this home order."
    }

    public static func forBaby(_ name: String, _ language: ResolvedLanguage) -> String {
        language == .zh ? "给\(name)记录" : "Log for \(name)"
    }

    public static func feedingChoice(_ language: ResolvedLanguage) -> String {
        language == .zh ? "选择喂养方式" : "Choose a feeding method"
    }

    public static func amount(_ milliliters: Double, unit: VolumeUnit, _ language: ResolvedLanguage) -> String {
        let locale = Locale(identifier: language == .zh ? "zh_CN" : "en_US")
        return unit.format(milliliters: milliliters, locale: locale)
    }

    public static func clock(_ date: Date, _ language: ResolvedLanguage) -> String {
        let locale = Locale(identifier: language == .zh ? "zh_CN" : "en_US")
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }
}
