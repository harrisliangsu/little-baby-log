import Foundation
import Testing
@testable import BabyLogKit

struct BabyCultureTests {
    @Test func zodiacFollowsLunarNewYearFromTheHongKongObservatory() {
        let before = BabyCulture.profile(year: 2024, month: 2, day: 9, hour: 12, minute: 0, timeZoneID: "Asia/Shanghai")
        let day = BabyCulture.profile(year: 2024, month: 2, day: 10, hour: 12, minute: 0, timeZoneID: "Asia/Shanghai")
        #expect(before.zodiac == "兔")
        #expect(day.zodiac == "龙")
        #expect(day.lunar.contains("正月"))
    }

    @Test func yearPillarChangesAtLiChunNotAtLunarNewYear() {
        // Hong Kong Observatory: 立春 2024-02-04, 春节 2024-02-10.
        // lunar-swift 1.1.9 EightCharTests maps 2024-02-05 08:00 to 甲辰年 丙寅月.
        let before = BabyCulture.profile(year: 2024, month: 2, day: 3, hour: 12, minute: 0, timeZoneID: "Asia/Shanghai")
        let after = BabyCulture.profile(year: 2024, month: 2, day: 5, hour: 8, minute: 0, timeZoneID: "Asia/Shanghai")
        #expect(before.year == "癸卯")
        #expect(after.year == "甲辰")
        #expect(after.month == "丙寅")
        #expect(before.zodiac == "兔")
        #expect(after.timeZoneID == "Asia/Shanghai")
    }

    @Test func monthPillarChangesOnJieNotOnZhongQi() {
        // 雨水 2024-02-19 is a 中气. 惊蛰 2024-03-05 is the next 节.
        let rain = BabyCulture.profile(year: 2024, month: 2, day: 19, hour: 12, minute: 0, timeZoneID: "Asia/Shanghai")
        let afterJingZhe = BabyCulture.profile(year: 2024, month: 3, day: 6, hour: 12, minute: 0, timeZoneID: "Asia/Shanghai")
        #expect(rain.month == "丙寅")
        #expect(afterJingZhe.month == "丁卯")
    }

    @Test func storedZoneDoesNotFollowThePhone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2024, month: 2, day: 4, hour: 16))!
        let shanghai = BabyCulture.civil(date: date, timeZoneID: "Asia/Shanghai")
        let asUTC = BabyCulture.civil(date: date, timeZoneID: "UTC")
        #expect(shanghai.day == 5)
        #expect(shanghai.hour == 0)
        #expect(asUTC.day == 4)
        #expect(asUTC.hour == 16)
        let unknown = BabyCulture.civil(date: date, timeZoneID: "Not/AZone")
        #expect(unknown.day == shanghai.day)
    }

    @Test func leapMonthStaysMarked() {
        let profile = BabyCulture.profile(year: 2023, month: 3, day: 22, hour: nil, minute: nil, timeZoneID: "Asia/Shanghai")
        #expect(profile.lunar.contains("闰"))
        #expect(profile.hour == nil)
    }

    @Test func lateZiKeepsTheSameDayPillar() {
        let evening = BabyCulture.profile(year: 2024, month: 6, day: 1, hour: 22, minute: 30, timeZoneID: "Asia/Shanghai")
        let late = BabyCulture.profile(year: 2024, month: 6, day: 1, hour: 23, minute: 30, timeZoneID: "Asia/Shanghai")
        #expect(evening.day == late.day)
        #expect(evening.hour != late.hour)
    }

    @Test func signUsesTheLibraryDateTable() {
        let pisces = BabyCulture.profile(year: 2024, month: 3, day: 20, hour: 12, minute: 0, timeZoneID: "Asia/Shanghai")
        let aries = BabyCulture.profile(year: 2024, month: 3, day: 21, hour: 12, minute: 0, timeZoneID: "Asia/Shanghai")
        #expect(pisces.sign == "双鱼")
        #expect(aries.sign == "白羊")
    }
}
