import Foundation
import BabyLogKit

/// Keys and defaults for `@AppStorage`.
///
///     @AppStorage(Prefs.volumeUnit) private var volumeUnit: VolumeUnit = Prefs.defaultVolumeUnit
enum Prefs {
    static let selectedBabyID = "selectedBabyID"
    static let volumeUnit = "volumeUnit"
    static let unitSystem = "unitSystem"
    /// `HistoryMode` raw value: the History tab shows the daily recap or the full list.
    static let historyMode = "historyMode"

    /// `AppearanceMode` raw value.
    static let appearanceMode = "appearanceMode"
    /// Minutes since midnight. Night on a schedule runs from start to end, wrapping past midnight.
    static let nightStartMinutes = "nightStartMinutes"
    static let nightEndMinutes = "nightEndMinutes"
    /// Lower the screen brightness while Night is showing.
    static let dimScreenAtNight = "dimScreenAtNight"
    /// Keep the screen on while the nursing timer is open. Off by default: it costs battery.
    static let keepScreenOnWhileNursing = "keepScreenOnWhileNursing"
    /// When false, the same private.sqlite stays local even if this build has a CloudKit container.
    static let cloudSyncEnabled = "cloudSyncEnabled"

    static let defaultAppearanceMode = AppearanceMode.system

    /// 宝宝小记 defaults to millilitres and metric, including on an English simulator.
    static var defaultVolumeUnit: VolumeUnit { .milliliters }

    static var defaultUnitSystem: UnitSystem { .metric }
}
