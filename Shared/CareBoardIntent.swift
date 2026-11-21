import AppIntents
import BabyLogKit

/// One slot in the system Edit Widget screen. `none` leaves that place empty.
enum WidgetCareItem: String, AppEnum {
    case none
    case breast
    case formula
    case wet
    case dirty
    case diaperChange
    case sleep

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "项目")

    static var caseDisplayRepresentations: [WidgetCareItem: DisplayRepresentation] {
        [
            .none: DisplayRepresentation(title: "不显示"),
            .breast: DisplayRepresentation(title: "亲喂"),
            .formula: DisplayRepresentation(title: "奶粉"),
            .wet: DisplayRepresentation(title: "小便"),
            .dirty: DisplayRepresentation(title: "大便"),
            .diaperChange: DisplayRepresentation(title: "换尿布"),
            .sleep: DisplayRepresentation(title: "睡眠"),
        ]
    }

    var card: HomeCard? {
        switch self {
        case .none: return nil
        case .breast: return .breast
        case .formula: return .formula
        case .wet: return .wet
        case .dirty: return .dirty
        case .diaperChange: return .diaperChange
        case .sleep: return .sleep
        }
    }
}

/// Per-widget configuration stored by the system, not by the home-card order.
struct CareBoardIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "宝宝小记"
    static var description = IntentDescription("每个小组件自己选择宝宝和项目顺序。这不改变首页卡片。")

    @Parameter(title: "宝宝")
    var baby: BabyEntity?

    @Parameter(title: "第 1 项", default: .formula)
    var first: WidgetCareItem

    @Parameter(title: "第 2 项", default: .wet)
    var second: WidgetCareItem

    @Parameter(title: "第 3 项", default: .none)
    var third: WidgetCareItem

    @Parameter(title: "第 4 项", default: .none)
    var fourth: WidgetCareItem

    @Parameter(title: "第 5 项", default: .none)
    var fifth: WidgetCareItem

    @Parameter(title: "第 6 项", default: .none)
    var sixth: WidgetCareItem

    var cards: [HomeCard] {
        let picked = [first, second, third, fourth, fifth, sixth].compactMap(\.card)
        let unique = WidgetBoard.unique(picked)
        return unique.isEmpty ? [.formula, .wet] : unique
    }

    init() {}
}
