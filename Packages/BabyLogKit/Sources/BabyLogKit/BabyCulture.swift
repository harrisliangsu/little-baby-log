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
        /// The zone the caller already used to read the civil clock. It is not applied a second time.
        public var timeZoneID: String
    }

    /// Civil numbers in the stored zone. An unknown zone id falls back to Asia/Shanghai, never the phone zone.
    public static func civil(date: Date, timeZoneID: String) -> (year: Int, month: Int, day: Int, hour: Int, minute: Int) {
        let zone = TimeZone(identifier: timeZoneID) ?? TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return (parts.year ?? 1, parts.month ?? 1, parts.day ?? 1, parts.hour ?? 0, parts.minute ?? 0)
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
        let month = lunar.monthInChinese.hasSuffix("月") ? lunar.monthInChinese : lunar.monthInChinese + "月"
        let lunarText = "\(lunar.year)年\(month)\(lunar.dayInChinese)"
        return Profile(
            lunar: lunarText,
            zodiac: lunar.yearShengXiao,
            sign: solar.xingZuo,
            year: eight.year,
            month: eight.month,
            day: eight.day,
            hour: hour == nil ? nil : eight.time,
            timeZoneID: timeZoneID
        )
    }
}
