package app.supare.offline

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.content.ContextCompat
import org.json.JSONObject

class AlarmScheduler(private val context: Context) {
    val manager = context.getSystemService(AlarmManager::class.java)
    val store = AlarmStore(context)
    fun exactAllowed() = Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()
    fun notificationsAllowed(): Boolean = androidx.core.app.NotificationManagerCompat.from(context).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    fun fullscreenAllowed(): Boolean = Build.VERSION.SDK_INT < 34 || context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
    private fun pending(id: String, due: Long): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, AlarmReceiver::class.java).setData(Uri.parse("supare://alarm/${Uri.encode(id)}"))
            .putExtra("id", id).putExtra("dueMillis", due), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun schedule(task: JSONObject, persist: Boolean = true) {
        require(task.getString("id").isNotBlank() && task.getString("title").isNotBlank()) { "A reminder needs an id and title" }
        val due = task.getLong("dueMillis")
        require(due > System.currentTimeMillis()) { "Choose a future reminder time" }
        require(notificationsAllowed()) { "Notifications are disabled. Enable them in Settings before scheduling reminders." }
        val alarm = task.optString("mode", "normal") == "alarm"
        if (alarm && !exactAllowed()) throw SecurityException("Exact alarm access is required for alarm reminders")
        val operation = pending(task.getString("id"), due)
        if (persist) {
            val saved = JSONObject(task.toString()).put("fired",false)
            val previous = store.get(task.getString("id"))
            val anchor = java.util.Calendar.getInstance().apply { timeInMillis = due }.get(java.util.Calendar.DAY_OF_MONTH)
            saved.put("anchorDay", if (task.optInt("anchorDay",0) in 1..31) task.getInt("anchorDay") else if (previous != null && previous.optLong("dueMillis") == due) previous.optInt("anchorDay",anchor) else anchor)
            if (previous != null && previous.optLong("dueMillis") == due && previous.has("recurrenceDue") && !saved.has("recurrenceDue")) saved.put("recurrenceDue",previous.getLong("recurrenceDue"))
            store.put(saved)
        }
        try {
            if (alarm) {
                val show = PendingIntent.getActivity(context, task.getString("id").hashCode(), Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                manager.setAlarmClock(AlarmManager.AlarmClockInfo(due, show), operation)
            } else if (exactAllowed()) manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, operation)
            else manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, operation)
        } catch (error: Exception) { if (persist) store.remove(task.getString("id")); throw error }
    }
    fun cancel(id: String) {
        manager.cancel(pending(id, 0))
        context.getSystemService(NotificationManager::class.java).cancel(id, 2)
        AlarmService.stopIfActive(context, id)
        context.sendBroadcast(Intent(AlarmService.CLOSED).setPackage(context.packageName).putExtra("id",id))
        store.remove(id)
    }
    fun restoreAll() {
        for (task in store.tasks()) {
            if (task.optBoolean("fired", false)) continue
            if (task.getLong("dueMillis") <= System.currentTimeMillis()) {
                // Reboot does not surprise users by replaying old alarms. Keep tasks pending and advance recurring ones.
                var next = AlarmMath.next(task, task.getLong("dueMillis"))
                var attempts = 0
                while (next != null && next <= System.currentTimeMillis() && attempts++ < 10000) next = AlarmMath.next(task, next)
                if (next == null || next <= System.currentTimeMillis()) { task.put("fired", true); store.put(task); continue }
                task.put("dueMillis", next); store.put(task); store.action(task.getString("id"), "fired", due = next)
            }
            try { schedule(task, false) } catch (_: Exception) { /* Existing task remains available for explicit repair on open. */ }
        }
    }
    fun channels() {
        if (Build.VERSION.SDK_INT < 26) return
        val notifications = context.getSystemService(NotificationManager::class.java)
        notifications.createNotificationChannel(NotificationChannel("supare_alarm_v1", "Task alarms", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Ringing task reminders. Sound is played by the alarm service."; setSound(null, null); enableVibration(false); lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        })
        notifications.createNotificationChannel(NotificationChannel("supare_reminder_v1", "Task reminders", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "Normal task and renewal reminders" })
    }
}
