package app.supare.offline

import android.content.Context
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Clicks the production AlarmActivity buttons; receiver-only tests cannot catch View.id/task-id shadowing. */
class AlarmUiDeviceTest {
    private fun awaitCondition(message: String, predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis()+20000
        while (!predicate() && System.currentTimeMillis()<deadline) Thread.sleep(100)
        assertTrue(message,predicate())
    }
    private fun button(view: View,label: String): Button? {
        if (view is Button && view.text.toString()==label) return view
        if (view is ViewGroup) for (index in 0 until view.childCount) button(view.getChildAt(index),label)?.let { return it }
        return null
    }
    private fun click(activity: AlarmActivity,label: String) {
        var clicked = false
        InstrumentationRegistry.getInstrumentation().runOnMainSync { clicked = button(activity.window.decorView,label)?.performClick() ?: false }
        assertTrue("The actual native button must exist and invoke its click listener: $label",clicked)
    }
    private fun withRingingActivity(operation: (Context,AlarmScheduler,String,Long,AlarmActivity) -> Unit) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val scheduler = AlarmScheduler(context)
        assumeTrue("Grant notifications/exact access before UI alarm tests",scheduler.notificationsAllowed() && scheduler.exactAllowed())
        val id = "instrumentation-ui-${System.nanoTime()}"
        val due = System.currentTimeMillis()+2500
        var activity: AlarmActivity? = null
        try {
            scheduler.channels()
            scheduler.schedule(JSONObject().put("id",id).put("title","Supare real native button test").put("dueMillis",due).put("mode","alarm").put("repeat","none"))
            awaitCondition("AlarmManager must start the real native foreground alarm before UI interaction") { AlarmService.activeId==id }
            activity = instrumentation.startActivitySync(Intent(context,AlarmActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                .putExtra("id",id).putExtra("title","Supare real native button test")) as AlarmActivity
            operation(context,scheduler,id,due,activity)
        } finally {
            scheduler.cancel(id)
            scheduler.store.ack(scheduler.store.drain().filter { it["id"]==id }.map { "${it["atMillis"]}:$id:${it["action"]}" })
            activity?.let { opened -> instrumentation.runOnMainSync { if (!opened.isFinishing) opened.finish() } }
        }
    }
    @Test fun actualSnoozeButtonsSilenceAndScheduleSelectedFiveTenFifteenMinutes() {
        for (minutes in listOf(5,10,15)) withRingingActivity { _,scheduler,id,_,activity ->
            val before = System.currentTimeMillis()
            click(activity,"Snooze $minutes minutes")
            awaitCondition("The actual Snooze button must silence the task's native alarm") { AlarmService.activeId!=id }
            val task = scheduler.store.get(id)!!
            val future = task.getLong("dueMillis")
            assertTrue("Snooze must persist the selected future interval",future>=before+minutes*60000L && future<=System.currentTimeMillis()+minutes*60000L)
            assertFalse(task.optBoolean("fired",true))
            val event = scheduler.store.drain().single { it["id"]==id && it["action"]=="snooze" }
            assertEquals(minutes,event["minutes"])
            assertEquals(future,event["dueMillis"])
        }
    }
    @Test fun actualDoneButtonSilencesCancelsAndQueuesCompletionForCorrectTask() = withRingingActivity { _,scheduler,id,due,activity ->
        click(activity,"Done")
        awaitCondition("The actual Done button must silence and cancel its one-time task") { AlarmService.activeId!=id && scheduler.store.get(id)==null }
        val event = scheduler.store.drain().single { it["id"]==id && it["action"]=="done" }
        assertEquals(due,event["occurrenceMillis"])
    }
    @Test fun actualStopButtonSilencesAndKeepsTaskUnfinished() = withRingingActivity { _,scheduler,id,_,activity ->
        click(activity,"Stop · keep task pending")
        awaitCondition("The actual Stop button must silence its task") { AlarmService.activeId!=id }
        assertNotNull("Stopping must preserve the unfinished native task",scheduler.store.get(id))
        val events = scheduler.store.drain().filter { it["id"]==id }
        assertTrue(events.any { it["action"]=="stop" })
        assertFalse(events.any { it["action"]=="done" })
    }
}
