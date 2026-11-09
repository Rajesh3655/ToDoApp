package app.supare.offline

import org.junit.Assert.*
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

class AlarmMathTest {
    private fun date(year: Int, month: Int, day: Int, hour: Int = 10): Long = Calendar.getInstance().apply {
        clear(); set(year,month - 1,day,hour,30)
    }.timeInMillis
    @Test fun oneTimeHasNoNextOccurrence() { assertNull(AlarmMath.next("none",1,date(2026,11,15))) }
    @Test fun dailyAdvancesCalendarDay() { assertEquals(date(2026,11,16),AlarmMath.next("daily",1,date(2026,11,15))) }
    @Test fun weeklyAdvancesSevenDays() { assertEquals(date(2026,11,22),AlarmMath.next("weekly",1,date(2026,11,15))) }
    @Test fun monthlyClampsToLastDay() { assertEquals(date(2027,2,28),AlarmMath.next("monthly",1,date(2027,1,31))) }
    @Test fun monthlyRetainsOriginalAnchorAfterShortMonth() {
        val february = AlarmMath.next("monthly",1,date(2027,1,31),31)!!
        assertEquals(date(2027,3,31),AlarmMath.next("monthly",1,february,31))
    }
    @Test fun customIntervalIsBounded() { assertEquals(date(2026,11,16),AlarmMath.next("custom",0,date(2026,11,15))); assertEquals(date(2026,11,18),AlarmMath.next("custom",3,date(2026,11,15))) }
    @Test fun dailyPreservesWallClockAcrossDaylightSaving() {
        val before = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
            val due = date(2027,3,13)
            val next = AlarmMath.next("daily",1,due)!!
            assertEquals(date(2027,3,14),next)
            assertEquals(23L * 60 * 60 * 1000,next-due)
        } finally { TimeZone.setDefault(before) }
    }
}
