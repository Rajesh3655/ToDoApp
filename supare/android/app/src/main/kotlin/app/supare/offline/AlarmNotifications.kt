package app.supare.offline

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import org.json.JSONObject

object AlarmNotifications {
    fun actionIntent(context: Context, id: String, action: String, minutes: Int = 0): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, AlarmActionReceiver::class.java).setData(Uri.parse("supare://action/${Uri.encode(id)}/$action/$minutes"))
            .putExtra("id", id).putExtra("action", action).putExtra("minutes", minutes), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun alarm(context: Context, task: JSONObject): Notification {
        val id = task.getString("id")
        val full = PendingIntent.getActivity(context, 0,
            Intent(context, AlarmActivity::class.java).setData(Uri.parse("supare://ring/${Uri.encode(id)}"))
                .putExtra("id", id).putExtra("title", task.getString("title")), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = NotificationCompat.Builder(context, "supare_alarm_v1")
            .setSmallIcon(R.drawable.ic_notification).setContentTitle(task.getString("title"))
            .setContentText("Task alarm · Done, Snooze or Stop")
            .setStyle(NotificationCompat.BigTextStyle().bigText(task.getString("title")))
            .setCategory(NotificationCompat.CATEGORY_ALARM).setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC).setOngoing(true).setContentIntent(full)
            .setDeleteIntent(actionIntent(context,id,"stop")).setSilent(true)
            .addAction(0,"Done",actionIntent(context,id,"done"))
            .addAction(0,"Snooze 10 min",actionIntent(context,id,"snooze",10))
            .addAction(0,"Stop",actionIntent(context,id,"stop"))
        if (AlarmScheduler(context).fullscreenAllowed()) builder.setFullScreenIntent(full,true)
        return builder.build()
    }
    fun normal(context: Context, task: JSONObject): Notification {
        val id = task.getString("id")
        val open = PendingIntent.getActivity(context,0,Intent(context,MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(context,"supare_reminder_v1").setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(task.getString("title")).setContentText(task.optString("body"))
            .setStyle(NotificationCompat.BigTextStyle().bigText(task.getString("title")))
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setAutoCancel(true).setContentIntent(open)
            .addAction(0,"Done",actionIntent(context,id,"done"))
            .addAction(0,"Snooze 10 min",actionIntent(context,id,"snooze",10))
            .setDeleteIntent(actionIntent(context,id,"stop")).build()
    }
}
