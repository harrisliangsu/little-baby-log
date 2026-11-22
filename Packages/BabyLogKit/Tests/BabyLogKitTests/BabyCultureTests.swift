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
        let before = BabyCulture.profile(year: 2024, month: 2, day: 3, hour: 12, minute: 0, timeZoneID: "Asia/Shanghai")
        let after = BabyCulture.profile(year: 2024, month: 2, day: 5, hour: 12, minute: 0, timeZoneID: "Asia/Shanghai")
        #expect(before.year == "癸卯")
        #expect(after.year == "甲辰")
        #expect(before.zodiac == "兔")
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
