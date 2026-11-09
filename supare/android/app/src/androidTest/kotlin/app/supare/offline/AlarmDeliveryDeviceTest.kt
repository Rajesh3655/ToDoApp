package app.supare.offline

import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Real Android AlarmManager delivery on a granted test installation; an emulator cannot validate audible output/physical lock screens. */
class AlarmDeliveryDeviceTest {
    @Test fun exactAlarmStartsNativeServiceAndCancellationStopsIt() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scheduler = AlarmScheduler(context)
        assumeTrue("Notifications/exact-alarm access must be granted for this delivery test",scheduler.notificationsAllowed() && scheduler.exactAllowed())
        val id = "instrumentation-delivery-${System.nanoTime()}"
        try {
            scheduler.channels()
            scheduler.schedule(JSONObject().put("id",id).put("title","Supare native alarm test")
                .put("dueMillis",System.currentTimeMillis()+2500).put("mode","alarm").put("repeat","none"))
            val deadline = System.currentTimeMillis()+15000
            while (AlarmService.activeId != id && System.currentTimeMillis() < deadline) Thread.sleep(100)
            assertEquals("AlarmManager receiver must launch the real native foreground service",id,AlarmService.activeId)
            scheduler.cancel(id)
            val stopDeadline = System.currentTimeMillis()+3000
            while (AlarmService.activeId == id && System.currentTimeMillis() < stopDeadline) Thread.sleep(50)
            assertNotEquals(id,AlarmService.activeId)
        } finally { scheduler.cancel(id) }
    }
    private fun awaitCondition(message: String, timeout: Long = 15000, predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis()+timeout
        while (!predicate() && System.currentTimeMillis() < deadline) Thread.sleep(100)
        assertTrue(message,predicate())
    }
    private fun acknowledgeOwnEvents(scheduler: AlarmScheduler,id: String) {
        val keys = scheduler.store.drain().filter { it["id"] == id }.map { "${it["atMillis"]}:$id:${it["action"]}" }
        scheduler.store.ack(keys)
    }
    @Test fun nativeSnoozeActionStopsRingingAndPersistsFiveMinuteAlarm() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scheduler = AlarmScheduler(context)
        assumeTrue(scheduler.notificationsAllowed() && scheduler.exactAllowed())
        val id = "instrumentation-snooze-${System.nanoTime()}"
        try {
            scheduler.channels()
            scheduler.schedule(JSONObject().put("id",id).put("title","Snooze integration test")
                .put("dueMillis",System.currentTimeMillis()+2500).put("mode","alarm").put("repeat","none"))
            awaitCondition("The native alarm must ring before snoozing") { AlarmService.activeId == id }
            val before = System.currentTimeMillis()
            context.sendBroadcast(android.content.Intent(context,AlarmActionReceiver::class.java).putExtra("id",id).putExtra("action","snooze").putExtra("minutes",5))
            awaitCondition("Snooze must silence the current native service") { AlarmService.activeId != id }
            val scheduled = scheduler.store.get(id)!!
            val due = scheduled.getLong("dueMillis")
            assertTrue(due >= before + 5*60000L && due <= System.currentTimeMillis()+5*60000L)
            assertFalse(scheduled.optBoolean("fired",true))
            val event = scheduler.store.drain().single { it["id"] == id && it["action"] == "snooze" }
            assertEquals(5,event["minutes"])
            assertEquals(due,event["dueMillis"])
        } finally { scheduler.cancel(id); acknowledgeOwnEvents(scheduler,id) }
    }
    @Test fun nativeDoneActionStopsRingingAndQueuesDurableCompletion() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scheduler = AlarmScheduler(context)
        assumeTrue(scheduler.notificationsAllowed() && scheduler.exactAllowed())
        val id = "instrumentation-done-${System.nanoTime()}"
        val due = System.currentTimeMillis()+2500
        try {
            scheduler.channels()
            scheduler.schedule(JSONObject().put("id",id).put("title","Done integration test").put("dueMillis",due).put("mode","alarm").put("repeat","none"))
            awaitCondition("The native alarm must ring before Done") { AlarmService.activeId == id }
            context.sendBroadcast(android.content.Intent(context,AlarmActionReceiver::class.java).putExtra("id",id).putExtra("action","done"))
            awaitCondition("Done must stop the native service and cancel a one-time alarm") { AlarmService.activeId != id && scheduler.store.get(id) == null }
            val event = scheduler.store.drain().single { it["id"] == id && it["action"] == "done" }
            assertEquals(due,event["occurrenceMillis"])
            assertTrue(scheduler.store.drain().any { it["id"] == id && it["action"] == "done" })
        } finally { scheduler.cancel(id); acknowledgeOwnEvents(scheduler,id) }
    }
    @Test fun cancelledExactAlarmDoesNotDeliver() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val scheduler = AlarmScheduler(context)
        assumeTrue("Notifications/exact-alarm access must be granted for this delivery test",scheduler.notificationsAllowed() && scheduler.exactAllowed())
        val id = "instrumentation-cancel-${System.nanoTime()}"
        scheduler.schedule(JSONObject().put("id",id).put("title","Cancelled alarm test")
            .put("dueMillis",System.currentTimeMillis()+1500).put("mode","alarm").put("repeat","none"))
        scheduler.cancel(id)
        Thread.sleep(2500)
        assertNotEquals(id,AlarmService.activeId)
        assertNull(scheduler.store.get(id))
    }
}
