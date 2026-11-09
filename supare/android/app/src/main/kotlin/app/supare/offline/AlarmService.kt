package app.supare.offline

import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import org.json.JSONObject

class AlarmService : Service() {
    companion object {
        const val CLOSED = "app.supare.offline.ALARM_CLOSED"
        @Volatile var activeId: String? = null
        fun stopIfActive(context: Context, id: String) {
            if (activeId == id) context.startService(Intent(context, AlarmService::class.java).setAction("cancel").putExtra("id",id))
        }
    }
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    override fun onBind(intent: Intent?): IBinder? = null
    private fun stopOutput() {
        handler.removeCallbacksAndMessages(null)
        player?.let {
            it.setOnPreparedListener(null); it.setOnErrorListener(null)
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }; player = null
        vibrator?.cancel(); vibrator = null
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "cancel") {
            if (intent.getStringExtra("id") == activeId) { stopOutput(); stopForeground(true); stopSelf(); activeId = null }
            return START_NOT_STICKY
        }
        val raw = intent?.getStringExtra("task") ?: run { stopSelf(); return START_NOT_STICKY }
        val task = JSONObject(raw)
        val id = task.getString("id")
        activeId?.takeIf { it != id }?.let {
            try { AlarmStore(this).action(it,"stop") } catch (_: Exception) {}
            sendBroadcast(Intent(CLOSED).setPackage(packageName).putExtra("id",it))
        }
        stopOutput(); activeId = id
        AlarmScheduler(this).channels()
        startForeground(1, AlarmNotifications.alarm(this,task))
        wakeLock = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"Supare:TaskAlarm").apply { acquire(10 * 60 * 1000L) }
        try {
            val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            player = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                setDataSource(this@AlarmService,sound); isLooping = true
                // Keep the service main looper responsive to Stop/Done while the media provider prepares sound.
                setOnPreparedListener { prepared -> if (player === prepared) { try { prepared.start() } catch (_: Exception) {} } }
                setOnErrorListener { _,_,_ -> true }
                prepareAsync()
            }
        } catch (_: Exception) { /* Notification remains available even if device has no ringtone. */ }
        vibrator = getSystemService(Vibrator::class.java)
        val vibrationAttributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
        if (android.os.Build.VERSION.SDK_INT >= 26) vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0,600,400,600,1400),0), vibrationAttributes)
        else vibrator?.vibrate(longArrayOf(0,600,400,600,1400),0, vibrationAttributes)
        handler.postDelayed({
            try { AlarmStore(this).action(id,"stop") } catch (_: Exception) {}
            sendBroadcast(Intent(CLOSED).setPackage(packageName).putExtra("id",id))
            stopOutput(); activeId = null; stopForeground(true); stopSelf()
        }, 10 * 60 * 1000L)
        return START_NOT_STICKY
    }
    override fun onDestroy() { stopOutput(); activeId = null; super.onDestroy() }
}
