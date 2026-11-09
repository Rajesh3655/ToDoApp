package app.supare.offline

import org.json.JSONObject
import java.util.Calendar

object AlarmMath {
    fun next(task: JSONObject, due: Long): Long? {
        return next(task.optString("repeat", "none"), task.optInt("intervalDays",1), due, task.optInt("anchorDay",0))
    }
    fun next(repeat: String, intervalDays: Int, due: Long, anchorDay: Int = 0): Long? {
        if (repeat == "none") return null
        val calendar = Calendar.getInstance().apply { timeInMillis = due }
        when (repeat) {
            "daily" -> calendar.add(Calendar.DAY_OF_YEAR, 1)
            "weekly" -> calendar.add(Calendar.DAY_OF_YEAR, 7)
            "monthly" -> {
                val day = if (anchorDay in 1..31) anchorDay else calendar.get(Calendar.DAY_OF_MONTH)
                calendar.set(Calendar.DAY_OF_MONTH,1); calendar.add(Calendar.MONTH,1)
                calendar.set(Calendar.DAY_OF_MONTH,minOf(day,calendar.getActualMaximum(Calendar.DAY_OF_MONTH)))
            }
            "custom" -> calendar.add(Calendar.DAY_OF_YEAR, intervalDays.coerceIn(1, 3650))
            else -> return null
        }
        return calendar.timeInMillis
    }
}
