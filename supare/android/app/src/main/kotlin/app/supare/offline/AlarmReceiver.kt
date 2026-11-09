package app.supare.offline

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        try {
            val scheduler = AlarmScheduler(context)
            val task = scheduler.store.fire(id, intent.getLongExtra("dueMillis", -1)) ?: return
            scheduler.store.get(id)?.takeIf { !it.optBoolean("fired", false) }?.let { scheduler.schedule(it, false) }
            scheduler.channels()
            if (task.optString("mode") == "alarm") {
                ContextCompat.startForegroundService(context, Intent(context, AlarmService::class.java).putExtra("task", task.toString()))
            } else {
                context.getSystemService(android.app.NotificationManager::class.java).notify(id, 2, AlarmNotifications.normal(context, task))
            }
        } catch (_: Exception) { Log.e("Supare", "Reminder delivery failed; open Supare to review permissions") }
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED")) return
        try { AlarmScheduler(context).restoreAll() } catch (_: Exception) { Log.e("Supare", "Could not restore reminder schedule") }
    }
}

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        val action = intent.getStringExtra("action") ?: return
        try {
            val scheduler = AlarmScheduler(context)
            when (action) {
                "done" -> {
                    scheduler.store.action(id, "done")
                    val task = scheduler.store.get(id)
                    if (task != null && task.optString("repeat", "none") != "none" && !task.optBoolean("fired",false)) {
                        // The next recurring occurrence must still ring before Flutter is reopened.
                        context.getSystemService(android.app.NotificationManager::class.java).cancel(id,2)
                        AlarmService.stopIfActive(context,id)
                    } else scheduler.cancel(id)
                }
                "snooze" -> {
                    val minutes = intent.getIntExtra("minutes", 10).takeIf { it in listOf(5, 10, 15) } ?: return
                    val task = scheduler.store.get(id) ?: return
                    val due = System.currentTimeMillis() + minutes * 60000L
                    if (task.optString("repeat", "none") != "none" && !task.optBoolean("fired",false) && task.getLong("dueMillis") > due && !task.has("recurrenceDue")) {
                        task.put("recurrenceDue",task.getLong("dueMillis"))
                    }
                    task.put("dueMillis", due).put("fired", false)
                    scheduler.schedule(task)
                    scheduler.store.action(id, "snooze", minutes, due)
                    context.getSystemService(android.app.NotificationManager::class.java).cancel(id, 2)
                    AlarmService.stopIfActive(context, id)
                }
                "stop" -> {
                    scheduler.store.action(id, "stop")
                    context.getSystemService(android.app.NotificationManager::class.java).cancel(id, 2)
                    AlarmService.stopIfActive(context, id)
                }
                else -> return
            }
            context.sendBroadcast(Intent(AlarmService.CLOSED).setPackage(context.packageName).putExtra("id", id))
        } catch (_: Exception) {
            // A revoked permission/storage failure must never leave the Stop button unable to silence ringing.
            AlarmService.stopIfActive(context,id)
            context.getSystemService(android.app.NotificationManager::class.java).cancel(id,2)
            context.sendBroadcast(Intent(AlarmService.CLOSED).setPackage(context.packageName).putExtra("id",id))
            android.widget.Toast.makeText(context,"Reminder action could not be saved. Open Supare to check permissions and the task.",android.widget.Toast.LENGTH_LONG).show()
            Log.e("Supare", "Could not apply reminder action")
        }
    }
}
