package app.supare.offline

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Task titles and the pending-action queue are never written as plaintext. */
class AlarmStore(private val context: Context) {
    companion object { private val mutex = Any(); private const val ALIAS = "supare.native.alarms.v1" }
    private val prefs get() = context.getSharedPreferences("supare_native_encrypted", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }
    private fun read(): JSONObject {
        val encoded = prefs.getString("data", null) ?: return JSONObject().put("tasks", JSONObject()).put("actions", JSONArray())
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        require(bytes.size >= 28) { "Invalid native alarm storage" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD("supare.native.v1".toByteArray())
        return JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
    }
    private fun write(data: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD("supare.native.v1".toByteArray())
        val bytes = cipher.iv + cipher.doFinal(data.toString().toByteArray(Charsets.UTF_8))
        check(prefs.edit().putString("data", Base64.encodeToString(bytes, Base64.NO_WRAP)).commit()) { "Cannot save native alarm state" }
    }
    fun tasks(): List<JSONObject> = synchronized(mutex) {
        val tasks = read().getJSONObject("tasks")
        tasks.keys().asSequence().map { JSONObject(tasks.getJSONObject(it).toString()) }.toList()
    }
    fun get(id: String): JSONObject? = synchronized(mutex) { read().getJSONObject("tasks").optJSONObject(id)?.let { JSONObject(it.toString()) } }
    fun put(task: JSONObject) = synchronized(mutex) { val data = read(); data.getJSONObject("tasks").put(task.getString("id"), task); write(data) }
    fun remove(id: String) = synchronized(mutex) { val data = read(); data.getJSONObject("tasks").remove(id); write(data) }
    fun fire(id: String, expectedDue: Long): JSONObject? = synchronized(mutex) {
        val data = read(); val tasks = data.getJSONObject("tasks"); val task = tasks.optJSONObject(id) ?: return@synchronized null
        if (task.getLong("dueMillis") != expectedDue || task.optBoolean("fired", false)) return@synchronized null
        val original = JSONObject(task.toString())
        task.put("lastFiredDue",expectedDue)
        var next = if (task.has("recurrenceDue") && task.optLong("recurrenceDue") > expectedDue) task.getLong("recurrenceDue") else AlarmMath.next(task, expectedDue)
        task.remove("recurrenceDue")
        var missed = 0
        while (next != null && next <= System.currentTimeMillis() && missed++ < 10000) next = AlarmMath.next(task,next)
        if (next != null && next > System.currentTimeMillis()) {
            task.put("dueMillis", next).put("fired", false)
            appendAction(data, id, "fired", 0, next)
        } else task.put("fired", true)
        write(data); original
    }
    private fun appendAction(data: JSONObject, id: String, action: String, minutes: Int, due: Long?) {
        val actions = data.getJSONArray("actions")
        // Repeated native occurrences do not grow the queue indefinitely while the app remains closed.
        for (index in actions.length()-1 downTo 0) {
            val prior = actions.getJSONObject(index)
            if (action != "done" && prior.optString("id") == id && prior.optString("action") == action) actions.remove(index)
        }
        while (actions.length() >= 4096) {
            val removable = (0 until actions.length()).firstOrNull { actions.getJSONObject(it).optString("action") != "done" } ?: 0
            actions.remove(removable)
        }
        val event = JSONObject().put("id", id).put("action", action).put("minutes", minutes).put("atMillis", System.currentTimeMillis())
        if (due != null) event.put("dueMillis", due)
        val occurrence = data.getJSONObject("tasks").optJSONObject(id)?.optLong("lastFiredDue",0) ?: 0L
        if (action == "done" && occurrence > 0L) event.put("occurrenceMillis",occurrence)
        actions.put(event)
    }
    fun action(id: String, action: String, minutes: Int = 0, due: Long? = null) = synchronized(mutex) {
        val data = read()
        if (action == "done") {
            val task = data.getJSONObject("tasks").optJSONObject(id) ?: return@synchronized
            val occurrence = task.optLong("lastFiredDue",0)
            if (occurrence > 0 && task.optLong("lastCompletedDue",-1) == occurrence) return@synchronized
            task.put("lastCompletedDue",occurrence)
        }
        appendAction(data,id,action,minutes,due); write(data)
    }
    fun drain(): List<Map<String, Any>> = synchronized(mutex) {
        val data = read(); val actions = data.getJSONArray("actions")
        val result = (0 until actions.length()).map { index -> val item = actions.getJSONObject(index); item.keys().asSequence().associateWith { item.get(it) } }
        result
    }
    fun ack(eventIds: List<String>) = synchronized(mutex) {
        val accepted = eventIds.toSet(); val data = read(); val actions = data.getJSONArray("actions")
        for (index in actions.length()-1 downTo 0) {
            val event = actions.getJSONObject(index)
            val key = "${event.getLong("atMillis")}:${event.getString("id")}:${event.getString("action")}" 
            if (key in accepted) actions.remove(index)
        }
        write(data)
    }
}
