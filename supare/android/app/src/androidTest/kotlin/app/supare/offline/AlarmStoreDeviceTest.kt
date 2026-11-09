package app.supare.offline

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Device tests; run on an isolated test installation. These do not claim physical-device alarm validation. */
class AlarmStoreDeviceTest {
    @Test fun encryptsTaskAndPreventsDuplicateDelivery() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = AlarmStore(context)
        val id = "instrumentation-encryption-${System.nanoTime()}"
        val due = System.currentTimeMillis() + 60000
        val title = "Highly private reminder ${System.nanoTime()}"
        try {
            store.put(JSONObject().put("id",id).put("title",title).put("dueMillis",due).put("repeat","none"))
            assertEquals(title,store.get(id)!!.getString("title"))
            val raw = context.getSharedPreferences("supare_native_encrypted",0).getString("data","")!!
            assertFalse(raw.contains(title)); assertFalse(raw.contains(id))
            assertNotNull(store.fire(id,due)); assertNull(store.fire(id,due))
        } finally { store.remove(id) }
    }
    @Test fun actionsRemainDurableUntilAcknowledged() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = AlarmStore(context)
        val id = "instrumentation-ack-${System.nanoTime()}"
        val due = System.currentTimeMillis() + 60000
        try {
            store.put(JSONObject().put("id",id).put("title","Test").put("dueMillis",due).put("repeat","none"))
            store.fire(id,due)
            store.action(id,"done")
            val first = store.drain().single { it["id"] == id }
            assertEquals(due,first["occurrenceMillis"])
            assertTrue(store.drain().any { it["id"] == id })
            val eventKey = "${first["atMillis"]}:$id:done"
            store.ack(listOf(eventKey))
            assertFalse(store.drain().any { it["id"] == id })
        } finally { store.remove(id) }
    }
    @Test fun rejectsStaleAlarmToken() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val store = AlarmStore(context)
        val id = "instrumentation-stale-${System.nanoTime()}"
        val due = System.currentTimeMillis() + 60000
        try {
            store.put(JSONObject().put("id",id).put("title","Test").put("dueMillis",due).put("repeat","none"))
            assertNull(store.fire(id,due-1)); assertNotNull(store.fire(id,due))
        } finally { store.remove(id) }
    }
}
