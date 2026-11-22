import Foundation
import LunarSwift

/// Culture facts derived from the saved birthday. Nothing here is stored, and nothing here is advice.
///
/// Rules, lunar-swift 1.1.9:
/// - Lunar date and 生肖 use the lunar new year, not 立春. A leap month stays negative in `month`.
/// - 八字 year uses the exact 立春 instant. Month uses the 节, not the 中气.
/// - Sect 2: the day pillar changes at local midnight. After 23:00 the hour pillar uses the next day's stem, and the day pillar stays today.
/// - 星座 is the library's fixed Gregorian date table, not the sun's longitude that year.
/// - True solar time is not used. The stored time zone is.
public enum BabyCulture {
    public static let algorithm = "lunar-swift-1.1.9"

    public struct Profile: Equatable, Sendable {
        public var lunar: String
        public var zodiac: String
        public var sign: String
        public var year: String
        public var month: String
        public var day: String
        public var hour: String?
    }

    public static func profile(year: Int, month: Int, day: Int, hour: Int?, minute: Int?, timeZoneID: String) -> Profile {
        let solar = Solar.fromYmdHms(
            year: year,
            month: month,
            day: day,
            hour: hour ?? 12,
            minute: minute ?? 0,
            second: 0
        )
        let lunar = solar.lunar
        let eight = lunar.eightChar
        eight.sect = 2
        let lunarText = "\(lunar.year)年\(lunar.monthInChinese)\(lunar.dayInChinese)"
        return Profile(
            lunar: lunarText,
            zodiac: lunar.yearShengXiao,
            sign: solar.xingZuo,
            year: eight.year,
            month: eight.month,
            day: eight.day,
            hour: hour == nil ? nil : eight.time
        )
    }
}
