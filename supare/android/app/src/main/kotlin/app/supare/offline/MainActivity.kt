package app.supare.offline

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private var secure = true
    private var previewResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        AlarmScheduler(this).channels()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"app.supare/native").setMethodCallHandler { call,result ->
            try {
                when (call.method) {
                    "getCapabilities" -> result.success(capabilities())
                    "scheduleTask" -> {
                        @Suppress("UNCHECKED_CAST") val map = call.arguments as? Map<String,Any?> ?: throw IllegalArgumentException("Invalid reminder")
                        val task = JSONObject(map)
                        require(task.getString("id").length <= 200 && task.getString("title").length <= 1000) { "Reminder too long" }
                        AlarmScheduler(this).schedule(task); result.success(true)
                    }
                    "cancelTask" -> {
                        val id = if (call.arguments is String) call.arguments as String else call.argument<String>("id")
                        require(!id.isNullOrEmpty()); AlarmScheduler(this).cancel(id); result.success(true)
                    }
                    "drainActions" -> result.success(AlarmStore(this).drain())
                    "ackActions" -> { AlarmStore(this).ack(call.argument<List<String>>("eventIds") ?: emptyList()); result.success(null) }
                    "setSecure" -> {
                        secure = if (call.arguments is Boolean) call.arguments as Boolean else call.argument<Boolean>("enabled") ?: call.argument<Boolean>("secure") ?: true
                        if (secure) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "requestAlarmPermissions" -> { requestPermissionsAndAccess(); result.success(capabilities()) }
                    "previewFile" -> {
                        check(previewResult == null) { "A preview is already open" }
                        val path = call.argument<String>("path") ?: throw IllegalArgumentException("Missing file")
                        val file = File(path).canonicalFile
                        require(file.isFile && isPrivateFile(file)) { "Only a Supare private temporary file can be previewed" }
                        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                        require(mime == "application/pdf" || mime.startsWith("image/")) { "This file format cannot be previewed" }
                        previewResult = result
                        startActivityForResult(Intent(this,PreviewActivity::class.java).putExtra("path",file.path).putExtra("mimeType",mime),9001)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: SecurityException) { result.error("ALARM_PERMISSION",error.message,null) }
            catch (error: Exception) { if (call.method == "previewFile") previewResult = null; result.error("NATIVE_ERROR",error.message ?: "Native operation failed",null) }
        }
    }
    private fun isPrivateFile(file: File): Boolean = listOf(cacheDir,filesDir).any { root -> file.path.startsWith(root.canonicalPath + File.separator) }
    private fun capabilities(): Map<String,Any> {
        val scheduler = AlarmScheduler(this)
        return mapOf("platform" to "android", "apiLevel" to Build.VERSION.SDK_INT,
            "exactAlarms" to scheduler.exactAllowed(), "notifications" to scheduler.notificationsAllowed(),
            "fullScreen" to scheduler.fullscreenAllowed(), "alarmKit" to false,
            "alarmNote" to "Android alarms require notification and exact-alarm access. Full-screen access is controlled by Android and store policy. Force-stop and some battery restrictions prevent delivery.")
    }
    private fun requestPermissionsAndAccess() {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(this,Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this,arrayOf(Manifest.permission.POST_NOTIFICATIONS),8001); return
        }
        val scheduler = AlarmScheduler(this)
        if (!scheduler.notificationsAllowed()) {
            if (Build.VERSION.SDK_INT >= 26) startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,packageName))
            else startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))
            return
        }
        if (Build.VERSION.SDK_INT >= 31 && !scheduler.exactAllowed()) {
            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,Uri.parse("package:$packageName"))); return
        }
        if (Build.VERSION.SDK_INT >= 34 && !scheduler.fullscreenAllowed()) {
            startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,Uri.parse("package:$packageName")))
        }
    }
    override fun onPause() { window.addFlags(WindowManager.LayoutParams.FLAG_SECURE); super.onPause() }
    override fun onResume() { super.onResume(); if (!secure) window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
    override fun onActivityResult(requestCode: Int,resultCode: Int,data: Intent?) {
        super.onActivityResult(requestCode,resultCode,data)
        if (requestCode == 9001) {
            val result = previewResult; previewResult = null
            val error = data?.getStringExtra("error")
            if (error != null) result?.error("PREVIEW_ERROR",error,null) else result?.success(null)
        }
    }
}
