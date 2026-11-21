import Foundation

/// User-visible strings for screens that are not the home cards. Chinese is the default.
public enum UICopy {
    public static func kind(_ kind: EventKind, _ language: ResolvedLanguage) -> String {
        switch (kind, language) {
        case (.sleep, .zh): return "睡眠"
        case (.breastfeed, .zh): return "亲喂"
        case (.bottle, .zh): return "奶粉"
        case (.solids, .zh): return "辅食"
        case (.diaper, .zh): return "尿布"
        case (.pump, .zh): return "吸奶"
        case (.growth, .zh): return "生长"
        case (.medicine, .zh): return "用药"
        case (_, .en): return kind.title
        }
    }

    public static func diaper(_ kind: DiaperKind, _ language: ResolvedLanguage) -> String {
        language == .zh ? ZhMirror.diaper(kind) : kind.title
    }

    public static func bottle(_ content: BottleContent, _ language: ResolvedLanguage) -> String {
        language == .zh ? ZhMirror.bottle(content) : content.title
    }

    public static func side(_ side: BreastSide, _ language: ResolvedLanguage) -> String {
        language == .zh ? (side == .left ? "左" : "右") : side.title
    }

    public static func t(_ key: Key, _ language: ResolvedLanguage) -> String {
        language == .zh ? key.zh : key.en
    }

    public enum Key {
        case welcome, welcomeBody, babyName, birthday, startTracking, inviteFootnote
        case otherLog, nothingToday, timeline
        case notes, deleteEntry, cancel, save, done, deleteConfirm, delete
        case editPrefix, newPrefix
        case start, end, stillAsleep, duration, timerRunning
        case leftMinutes, rightMinutes, lastSide, none, time, amount, contents, food
        case pumpDuration, left, right, weight, ounces, length, head, medicine, dose
        case discardFeed, discard, keepGoing, discardBody, total, started, close, finish, next
        case history, recap, list, noEntries, nothingHere, everythingShows, filter, everything
        case trends, days7, days14, days30, noTrends, trendsHint, noGrowth
        case upNext, rightNow, napWindow, bedtimeAround, nextFeedAround
        case recapTitle, goToDay, previousDay, nextDay, shareRecap, nothingLogged, asleep, now
        case babies, caregivers, appearance, nursingTimer, nightSchedule, nightLook, widgetAppearance
        case widgetHelp, lockHelp, widgetBaby, dataFootnote, about
        case aboutBody, signInICloud, iCloudRestricted, switchBaby
        case couldntOpen, notBorn, deleteBaby, deleteBabyBody
        case sinceEmpty, addBaby
        case futureStart, endAfterStart, sleepTooLong, enterNursing, enterAmount, enterPump, enterGrowth, enterMedicine

        var zh: String {
            switch self {
            case .welcome: return "欢迎使用宝宝小记"
            case .welcomeBody: return "亲喂、奶粉、尿布和睡眠，点一下就记下来。免费、离线可用，iCloud 可以以后再开。"
            case .babyName: return "宝宝名字"
            case .birthday: return "生日"
            case .startTracking: return "开始记录"
            case .inviteFootnote: return "如果另一位照顾者邀请了你，在这台手机上打开邀请。iCloud 同步后，宝宝会出现在这里。没登录 iCloud 也可以先在本地记。"
            case .otherLog: return "其他记录"
            case .nothingToday: return "今天还没有记录。"
            case .timeline: return "时间线"
            case .notes: return "备注"
            case .deleteEntry: return "删除这条记录"
            case .cancel: return "取消"
            case .save: return "保存"
            case .done: return "完成"
            case .deleteConfirm: return "删除这条记录？"
            case .delete: return "删除"
            case .editPrefix: return "修改"
            case .newPrefix: return "记录"
            case .start: return "开始"
            case .end: return "结束"
            case .stillAsleep: return "还在睡"
            case .duration: return "时长"
            case .timerRunning: return "计时还在进行。回到今天页面可以换边或结束。"
            case .leftMinutes: return "左侧分钟"
            case .rightMinutes: return "右侧分钟"
            case .lastSide: return "最后一侧"
            case .none: return "无"
            case .time: return "时间"
            case .amount: return "奶量"
            case .contents: return "内容"
            case .food: return "食物"
            case .pumpDuration: return "时长"
            case .left: return "左侧"
            case .right: return "右侧"
            case .weight: return "体重"
            case .ounces: return "盎司"
            case .length: return "身长"
            case .head: return "头围"
            case .medicine: return "药品"
            case .dose: return "剂量"
            case .discardFeed: return "放弃这次亲喂？"
            case .discard: return "放弃"
            case .keepGoing: return "继续"
            case .discardBody: return "已经记下的时间会被删掉。"
            case .total: return "总计"
            case .started: return "开始于"
            case .close: return "关闭"
            case .finish: return "完成"
            case .next: return "下一侧"
            case .history: return "历史"
            case .recap: return "回顾"
            case .list: return "列表"
            case .noEntries: return "还没有记录"
            case .nothingHere: return "这里没有"
            case .everythingShows: return "记下的内容都会出现在这里。"
            case .filter: return "筛选"
            case .everything: return "全部"
            case .trends: return "趋势"
            case .days7: return "7 天"
            case .days14: return "14 天"
            case .days30: return "30 天"
            case .noTrends: return "还没有趋势"
            case .trendsHint: return "记几次睡眠、喂奶和尿布后，图表会出现在这里。"
            case .noGrowth: return "记一条生长后，可以看到体重变化。"
            case .upNext: return "接下来"
            case .rightNow: return "现在"
            case .napWindow: return "小睡窗口"
            case .bedtimeAround: return "大约睡觉"
            case .nextFeedAround: return "大约下次喂奶"
            case .recapTitle: return "回顾"
            case .goToDay: return "跳到某一天"
            case .previousDay: return "前一天"
            case .nextDay: return "后一天"
            case .shareRecap: return "分享回顾"
            case .nothingLogged: return "没有记录"
            case .asleep: return "睡眠中"
            case .now: return "现在"
            case .babies: return "宝宝"
            case .caregivers: return "照顾者"
            case .appearance: return "外观"
            case .nursingTimer: return "亲喂计时"
            case .nightSchedule: return "夜间从这时开始，到这时结束。其余时间跟随手机的浅色或深色。"
            case .nightLook: return "夜间是偏暗、偏暖的纯黑外观，方便夜里喂奶。"
            case .widgetAppearance: return "小组件和实时活动跟随手机的浅色或深色。iOS 不允许应用改这个。"
            case .widgetHelp: return "在主屏幕空白处按住，点编辑，再点添加小组件，选择宝宝小记。可以不打开应用就开始亲喂或记尿布。"
            case .lockHelp: return "锁屏按住，点自定，在时钟下添加小组件。正在进行的睡眠和亲喂也会出现在锁屏和灵动岛。"
            case .widgetBaby: return "要在小组件里换宝宝，按住小组件再点编辑小组件。"
            case .dataFootnote: return "每个宝宝的每一条记录，一张表。"
            case .about: return "关于"
            case .aboutBody: return "宝宝小记（Little Baby Log）是自由软件，以 GNU GPL-3.0 及 App Store 附加许可发布。源自 Mo Garber 的 Little Baby Log。无账号、无广告、无追踪。没登录 iCloud 时数据只在这台设备上。"
            case .signInICloud: return "到系统设置登录 iCloud 后才能同步和分享。"
            case .iCloudRestricted: return "这台手机上的 iCloud 目前受限或不可用。"
            case .switchBaby: return "切换宝宝"
            case .couldntOpen: return "打不开数据"
            case .notBorn: return "还没出生？先填预产期，以后再改。"
            case .deleteBaby: return "删除宝宝和全部记录"
            case .deleteBabyBody: return "会删掉这个宝宝的每一条记录，包括已经分享出去的。不能撤销。"
            case .sinceEmpty: return "还没有记录。点下面的按钮开始。"
            case .addBaby: return "添加宝宝"
            case .futureStart: return "开始时间不能在将来。"
            case .endAfterStart: return "结束时间必须晚于开始。"
            case .sleepTooLong: return "一段睡眠不能超过 24 小时。"
            case .enterNursing: return "至少填一侧的亲喂时长。"
            case .enterAmount: return "请填写奶量。"
            case .enterPump: return "请填写吸奶量。"
            case .enterGrowth: return "至少填一项生长数据。"
            case .enterMedicine: return "请填写药名。"
            }
        }

        var en: String {
            switch self {
            case .welcome: return "Welcome to Little Baby Log"
            case .welcomeBody: return "Nursing, formula, diapers, and sleep. Tap to log. Free and offline. iCloud can wait."
            case .babyName: return "Baby's name"
            case .birthday: return "Birthday"
            case .startTracking: return "Start tracking"
            case .inviteFootnote: return "If another caregiver invited you, open the invite on this phone. After iCloud sync, the baby shows up here. You can log locally without iCloud."
            case .otherLog: return "Other"
            case .nothingToday: return "Nothing logged today."
            case .timeline: return "Timeline"
            case .notes: return "Notes"
            case .deleteEntry: return "Delete this entry"
            case .cancel: return "Cancel"
            case .save: return "Save"
            case .done: return "Done"
            case .deleteConfirm: return "Delete this entry?"
            case .delete: return "Delete"
            case .editPrefix: return "Edit"
            case .newPrefix: return "Log"
            case .start: return "Start"
            case .end: return "End"
            case .stillAsleep: return "Still asleep"
            case .duration: return "Duration"
            case .timerRunning: return "The timer is still running. Go back to Today to switch sides or finish."
            case .leftMinutes: return "Left minutes"
            case .rightMinutes: return "Right minutes"
            case .lastSide: return "Last side"
            case .none: return "None"
            case .time: return "Time"
            case .amount: return "Amount"
            case .contents: return "Contents"
            case .food: return "Food"
            case .pumpDuration: return "Duration"
            case .left: return "Left"
            case .right: return "Right"
            case .weight: return "Weight"
            case .ounces: return "Ounces"
            case .length: return "Length"
            case .head: return "Head"
            case .medicine: return "Medicine"
            case .dose: return "Dose"
            case .discardFeed: return "Discard this feed?"
            case .discard: return "Discard"
            case .keepGoing: return "Keep going"
            case .discardBody: return "The time you've tracked will be deleted."
            case .total: return "Total"
            case .started: return "Started"
            case .close: return "Close"
            case .finish: return "Finish"
            case .next: return "Next"
            case .history: return "History"
            case .recap: return "Recap"
            case .list: return "List"
            case .noEntries: return "No entries yet"
            case .nothingHere: return "Nothing here"
            case .everythingShows: return "Everything you log will show up here."
            case .filter: return "Filter"
            case .everything: return "Everything"
            case .trends: return "Trends"
            case .days7: return "7 days"
            case .days14: return "14 days"
            case .days30: return "30 days"
            case .noTrends: return "No trends yet"
            case .trendsHint: return "Log a few sleeps, feeds, and diapers and your charts will show up here."
            case .noGrowth: return "Log a growth entry to see weight over time."
            case .upNext: return "Up next"
            case .rightNow: return "Right now"
            case .napWindow: return "Nap window"
            case .bedtimeAround: return "Bedtime around"
            case .nextFeedAround: return "Next feed around"
            case .recapTitle: return "Recap"
            case .goToDay: return "Go to day"
            case .previousDay: return "Previous day"
            case .nextDay: return "Next day"
            case .shareRecap: return "Share recap"
            case .nothingLogged: return "Nothing logged"
            case .asleep: return "Asleep"
            case .now: return "Now"
            case .babies: return "Babies"
            case .caregivers: return "Caregivers"
            case .appearance: return "Appearance"
            case .nursingTimer: return "Nursing timer"
            case .nightSchedule: return "Night turns on and off at these times. Otherwise the app follows the phone's Light or Dark setting."
            case .nightLook: return "Night is a dim, warm, true-black look for feeding in the dark."
            case .widgetAppearance: return "Widgets and Live Activities follow the phone's Light or Dark setting. iOS doesn't let the app change that."
            case .widgetHelp: return "Touch and hold an empty spot on the Home Screen, tap Edit, then Add Widget, and choose Little Baby Log."
            case .lockHelp: return "On the Lock Screen, touch and hold, tap Customize, then add a widget under the clock."
            case .widgetBaby: return "To show a different baby, touch and hold the widget and tap Edit Widget."
            case .dataFootnote: return "A spreadsheet of every entry for every baby."
            case .about: return "About"
            case .aboutBody: return "Little Baby Log is free software under GPL-3.0 plus the App Store terms. It comes from Mo Garber's Little Baby Log. No account, no ads, no tracking. Without iCloud, data stays on this device."
            case .signInICloud: return "Sign in to iCloud in Settings to sync and share."
            case .iCloudRestricted: return "iCloud is restricted or unavailable on this phone right now."
            case .switchBaby: return "Switch baby"
            case .couldntOpen: return "Couldn't open your data"
            case .notBorn: return "Not born yet? Use the due date and update it later."
            case .deleteBaby: return "Delete baby and all entries"
            case .deleteBabyBody: return "This removes every entry for this baby, including ones you've shared. It can't be undone."
            case .sinceEmpty: return "Nothing logged yet. Tap a button below to get started."
            case .addBaby: return "Add a baby"
            case .futureStart: return "The start time can't be in the future."
            case .endAfterStart: return "The end time must be after the start time."
            case .sleepTooLong: return "A sleep can't be longer than 24 hours."
            case .enterNursing: return "Enter how long you nursed on at least one side."
            case .enterAmount: return "Enter the amount."
            case .enterPump: return "Enter the amount pumped."
            case .enterGrowth: return "Enter at least one measurement."
            case .enterMedicine: return "Enter the medicine name."
            }
        }
    }

    /// Maps the English validation string from `EventDraft` into the selected language.
    public static func validation(_ message: String, _ language: ResolvedLanguage) -> String {
        guard language == .zh else { return message }
        switch message {
        case "The start time can't be in the future.": return Key.futureStart.zh
        case "The end time must be after the start time.": return Key.endAfterStart.zh
        case "A sleep can't be longer than 24 hours.": return Key.sleepTooLong.zh
        case "Enter how long you nursed on at least one side.": return Key.enterNursing.zh
        case "Enter the amount.": return Key.enterAmount.zh
        case "Enter the amount pumped.": return Key.enterPump.zh
        case "Enter at least one measurement.": return Key.enterGrowth.zh
        case "Enter the medicine name.": return Key.enterMedicine.zh
        default: return message
        }
    }
}

/// Chinese names used by UICopy without pulling the app-only Zh enum into every call.
private enum ZhMirror {
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
}
