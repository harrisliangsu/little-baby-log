import SwiftUI
import WidgetKit

@main
struct LittleBabyLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        CareBoardWidget()
        LockScreenWidget()
        TimerLiveActivityWidget()
    }
}
