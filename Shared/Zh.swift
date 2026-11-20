import BabyLogKit
import Foundation

/// Chinese copy for the basic 宝宝小记 interface. Shared by the app and the widget extension.
enum Zh {
    static let appName = "宝宝小记"
    static let appNameEnglish = "Little Baby Log"
    static let emptyBaby = "打开宝宝小记，添加宝宝"
    static let noRecords = "还没有记录"
    static let recentNone = "还没有"
    static let sleepingNow = "睡眠中"
    static let justNow = "刚刚"

    static func kind(_ kind: EventKind) -> String {
        switch kind {
        case .sleep: return "睡眠"
        case .breastfeed: return "亲喂"
        case .bottle: return "奶粉"
        case .solids: return "辅食"
        case .diaper: return "尿布"
        case .pump: return "吸奶"
        case .growth: return "生长"
        case .medicine: return "用药"
        }
    }

    static func diaper(_ kind: DiaperKind) -> String {
        switch kind {
        case .wet: return "小便"
        case .dirty: return "大便"
        case .mixed: return "小便+大便"
        case .dry: return "换尿布"
        }
    }

    static func bottle(_ content: BottleContent) -> String {
        switch content {
        case .formula: return "奶粉"
        case .breastMilk: return "母乳"
        case .other: return "其他"
        }
    }

    static func side(_ side: BreastSide) -> String {
        side == .left ? "左" : "右"
    }

    static func count(_ n: Int) -> String { "\(n)次" }

    static func ml(_ value: Double) -> String {
        let whole = value.rounded()
        if abs(value - whole) < 0.05 {
            return "\(Int(whole)) ml"
        }
        return String(format: "%.1f ml", value)
    }

    static func ago(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return justNow }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)分钟前" }
        let hours = minutes / 60
        let remain = minutes % 60
        if hours < 24 {
            return remain == 0 ? "\(hours)小时前" : "\(hours)小时\(remain)分前"
        }
        return "\(hours / 24)天前"
    }

    /// One line the home-screen widget and the in-app preview both show, so they can't drift apart.
    static func widgetLine(_ title: String, _ window: CareRollup.Window) -> String {
        "\(title) 亲喂\(window.breastCount)次 奶粉\(window.formulaCount)次 \(ml(window.formulaML)) 小便\(window.wetCount) 大便\(window.dirtyCount) 换尿布\(window.diaperChangeCount) 睡眠\(window.sleepCount)"
    }
}
