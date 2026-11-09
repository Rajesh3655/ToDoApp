import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testOneTimeScheduleHasOneOccurrence() {
    let due = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertEqual(NativeSchedule.dates(due: due, repeatRule: "none", intervalDays: 1), [due])
  }

  func testWeeklyRecurrencePreservesCalendarTime() {
    let calendar = Calendar.current
    let due = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10, minute: 30))!
    let dates = NativeSchedule.dates(due: due, repeatRule: "weekly", intervalDays: 1)
    XCTAssertEqual(dates.count, 8)
    XCTAssertEqual(calendar.component(.hour, from: dates[1]), 10)
    XCTAssertEqual(calendar.component(.minute, from: dates[1]), 30)
    XCTAssertEqual(calendar.dateComponents([.day], from: dates[0], to: dates[1]).day, 7)
  }

  func testCustomRecurrenceIsBoundedAndNeverZero() {
    let due = Date(timeIntervalSince1970: 1_800_000_000)
    let dates = NativeSchedule.dates(due: due, repeatRule: "custom", intervalDays: 0)
    XCTAssertEqual(dates.count, 8)
    XCTAssertGreaterThan(dates[1], dates[0])
  }

  func testMonthlyRecurrenceClampsShortMonth() {
    let calendar = Calendar.current
    let due = calendar.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 10))!
    let dates = NativeSchedule.dates(due: due, repeatRule: "monthly", intervalDays: 1)
    XCTAssertEqual(calendar.component(.month, from: dates[1]), 2)
    XCTAssertEqual(calendar.component(.day, from: dates[1]), 28)
    XCTAssertEqual(calendar.component(.day, from: dates[2]), 31)
  }
  func testRefreshAfterHorizonKeepsOriginalMonthEndAnchor() {
    let calendar = Calendar.current
    let due = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 10))!
    let after = calendar.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 12))!
    let dates = NativeSchedule.futureDates(due: due, repeatRule: "monthly", intervalDays: 1, after: after)
    XCTAssertEqual(dates.count, 8)
    XCTAssertEqual(calendar.component(.month, from: dates[0]), 3)
    XCTAssertEqual(calendar.component(.day, from: dates[0]), 31)
    XCTAssertTrue(dates.allSatisfy { $0 > after })
  }

  func testClampedMonthlySchedulePreservesExplicitOriginalAnchor() {
    let calendar = Calendar.current
    let due = calendar.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 10))!
    let dates = NativeSchedule.dates(due: due, repeatRule: "monthly", intervalDays: 1, anchorDay: 31)
    XCTAssertEqual(calendar.component(.month, from: dates[1]), 3)
    XCTAssertEqual(calendar.component(.day, from: dates[1]), 31)
    XCTAssertEqual(calendar.component(.month, from: dates[2]), 4)
    XCTAssertEqual(calendar.component(.day, from: dates[2]), 30)
  }

}
