package app.supare.offline

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.content.ContextCompat

class AlarmActivity : Activity() {
    private var id = ""
    private val closed = object : BroadcastReceiver() { override fun onReceive(context: Context,intent: Intent) { if (intent.getStringExtra("id") == id) finish() } }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or WindowManager.LayoutParams.FLAG_SECURE)
        id = intent.getStringExtra("id") ?: run { finish(); return }
        if (AlarmService.activeId != id) { finish(); return }
        ContextCompat.registerReceiver(this,closed,IntentFilter(AlarmService.CLOSED),ContextCompat.RECEIVER_NOT_EXPORTED)
        render()
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); id = intent.getStringExtra("id") ?: ""; render() }
    private fun render() {
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (density * value).toInt()
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(dp(28),dp(48),dp(28),dp(32)) }
        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(layout) { view, insets ->
            val bars = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.systemBars())
            view.setPadding(dp(28) + bars.left,dp(48) + bars.top,dp(28) + bars.right,dp(32) + bars.bottom)
            insets
        }
        layout.addView(TextView(this).apply { text = "SUPARE  ·  TASK ALARM"; textSize = 14f; setTextColor(Color.parseColor("#BCE1BD")); gravity = Gravity.CENTER })
        layout.addView(TextView(this).apply { text = intent.getStringExtra("title") ?: "Task reminder"; textSize = 30f; setTextColor(Color.WHITE); gravity = Gravity.CENTER; setPadding(0,dp(36),0,dp(36)) })
        fun button(title: String, action: String, minutes: Int = 0) {
            layout.addView(Button(this).apply {
                text = title; isAllCaps = false; textSize = 18f
                layoutParams = LinearLayout.LayoutParams(-1,dp(60)).apply { topMargin = dp(12) }
                setOnClickListener { sendBroadcast(Intent(this@AlarmActivity,AlarmActionReceiver::class.java).putExtra("id",this@AlarmActivity.id).putExtra("action",action).putExtra("minutes",minutes)); finish() }
            })
        }
        button("Done", "done"); button("Snooze 5 minutes", "snooze",5); button("Snooze 10 minutes", "snooze",10); button("Snooze 15 minutes", "snooze",15); button("Stop · keep task pending", "stop")
        setContentView(ScrollView(this).apply { isFillViewport = true; addView(layout) })
    }
    override fun onDestroy() { try { unregisterReceiver(closed) } catch (_: Exception) {}; super.onDestroy() }
}
