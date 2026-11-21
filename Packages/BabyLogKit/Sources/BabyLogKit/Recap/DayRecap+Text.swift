import Foundation

extension DayRecap {
    /// The recap as plain text for people who do not have the app: a title, the summary, then one line per entry
    /// in time order. No notes, no names beyond the baby's.
    public func plainText(
        babyName: String,
        describer: EventDescriber,
        calendar: Calendar,
        locale: Locale = .current,
        language: ResolvedLanguage = .en
    ) -> String {
        let zh = language == .zh
        let dateStyle = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).month(.wide).day()
        let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        func time(_ date: Date) -> String {
            // Newer systems put a narrow no-break space before AM/PM; plain text wants an ordinary space.
            date.formatted(timeStyle).replacingOccurrences(of: "\u{202F}", with: " ")
        }

        var lines = ["\(babyName): \(dayStart.formatted(dateStyle))", ""]

        // Summary.
        let s = summary
        var sleep = (zh ? "睡眠：" : "Sleep: ") + DurationFormat.short(s.sleep)
        if napCount > 0 { sleep += zh ? "（\(napCount)次小睡）" : (napCount == 1 ? " (1 nap)" : " (\(napCount) naps)") }
        lines.append(sleep)
        var feeds = (zh ? "喂奶：" : "Feeds: ") + "\(s.feedCount)"
        var feedDetail: [String] = []
        if s.nursing > 0 { feedDetail.append((zh ? "亲喂 " : "nursing ") + DurationFormat.short(s.nursing)) }
        if s.bottleML > 0 { feedDetail.append((zh ? "奶瓶 " : "bottle ") + describer.volumeUnit.format(milliliters: s.bottleML, locale: describer.locale)) }
        if !feedDetail.isEmpty { feeds += (zh ? "（" : " (") + feedDetail.joined(separator: zh ? "，" : ", ") + (zh ? "）" : ")") }
        lines.append(feeds)
        var diapers = (zh ? "尿布：" : "Diapers: ") + "\(s.diaperCount)"
        if s.diaperCount > 0 {
            diapers += zh
                ? "（小便\(s.wetCount)，大便\(s.dirtyCount)）"
                : " (\(s.wetCount) wet, \(s.dirtyCount) dirty)"
        }
        lines.append(diapers)
        if s.solidsCount > 0 { lines.append((zh ? "辅食：" : "Solids: ") + "\(s.solidsCount)") }
        if s.medicineCount > 0 { lines.append((zh ? "用药：" : "Medicine: ") + "\(s.medicineCount)") }
        if s.pumpML > 0 {
            lines.append((zh ? "吸奶：" : "Pumped: ") + describer.volumeUnit.format(milliliters: s.pumpML, locale: describer.locale))
        }

        // Entries.
        var timeline: [String] = []
        if let carried = sleepSpans.first(where: { $0.continuesFromPreviousDay && $0.isRunning }),
           let since = carried.event.startDate {
            timeline.append(zh
                ? "从前一天睡到现在，" + time(since) + "开始"
                : "Still asleep since " + time(since) + " (from the day before)")
        }
        for hour in visibleHours {
            for entry in hour.entries {
                switch entry {
                case .event(let event):
                    let detail = describer.summary(for: event, now: now, language: language)
                    let title = UICopy.kind(event.kind, language)
                    timeline.append(time(entry.time) + "  " + title + (detail.isEmpty ? "" : (zh ? "：" : ": ") + detail))
                case .wakeUp(let event):
                    let slept = DurationFormat.short(event.duration(at: now))
                    timeline.append(zh
                        ? time(entry.time) + "  醒来（睡了\(slept)）"
                        : time(entry.time) + "  Woke up (slept " + slept + ")")
                }
            }
        }
        lines.append("")
        if timeline.isEmpty {
            lines.append(zh ? "没有记录。" : "Nothing logged.")
        } else {
            lines.append(contentsOf: timeline)
        }
        return lines.joined(separator: "\n")
    }
}
