package com.verint.verint_alarm_flutter.alarm

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class AlarmDefinition(
    val id: String,
    val label: String,
    val hour: Int,
    val minute: Int,
    val scheduledAtEpochMs: Long?,
    val daysOfWeek: Set<Int>,
    val snoozeMinutes: Int,
    val isEnabled: Boolean,
)

class AlarmStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun upsert(alarm: AlarmDefinition) {
        val values = loadMutable()
        values[alarm.id] = alarm
        persist(values)
    }

    fun remove(id: String) {
        val values = loadMutable()
        values.remove(id)
        persist(values)
    }

    fun get(id: String): AlarmDefinition? = loadMutable()[id]

    fun clear() {
        prefs.edit().remove(KEY_ALARMS).apply()
    }

    fun all(): List<AlarmDefinition> = loadMutable().values.toList()

    private fun loadMutable(): MutableMap<String, AlarmDefinition> {
        val raw = prefs.getString(KEY_ALARMS, null) ?: return mutableMapOf()
        return try {
            val root = JSONArray(raw)
            val result = mutableMapOf<String, AlarmDefinition>()
            for (i in 0 until root.length()) {
                val item = root.optJSONObject(i) ?: continue
                val id = item.optString("id")
                if (id.isBlank()) continue
                val days = mutableSetOf<Int>()
                val daysJson = item.optJSONArray("daysOfWeek") ?: JSONArray()
                for (j in 0 until daysJson.length()) {
                    val day = daysJson.optInt(j, -1)
                    if (day in 1..7) {
                        days.add(day)
                    }
                }
                result[id] = AlarmDefinition(
                    id = id,
                    label = item.optString("label", "Alarm"),
                    hour = item.optInt("hour", 7).coerceIn(0, 23),
                    minute = item.optInt("minute", 0).coerceIn(0, 59),
                    scheduledAtEpochMs = if (item.has("scheduledAtEpochMs") && !item.isNull("scheduledAtEpochMs")) {
                        item.optLong("scheduledAtEpochMs")
                    } else {
                        null
                    },
                    daysOfWeek = days,
                    snoozeMinutes = item.optInt("snoozeMinutes", 5).coerceIn(1, 60),
                    isEnabled = item.optBoolean("isEnabled", true),
                )
            }
            result
        } catch (_: Throwable) {
            mutableMapOf()
        }
    }

    private fun persist(values: Map<String, AlarmDefinition>) {
        val root = JSONArray()
        values.values.forEach { alarm ->
            val item = JSONObject()
                .put("id", alarm.id)
                .put("label", alarm.label)
                .put("hour", alarm.hour)
                .put("minute", alarm.minute)
                .put("scheduledAtEpochMs", alarm.scheduledAtEpochMs)
                .put("snoozeMinutes", alarm.snoozeMinutes)
                .put("isEnabled", alarm.isEnabled)
            val days = JSONArray()
            alarm.daysOfWeek.sorted().forEach { day ->
                days.put(day)
            }
            item.put("daysOfWeek", days)
            root.put(item)
        }
        prefs.edit().putString(KEY_ALARMS, root.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "verint_alarm_native_store"
        private const val KEY_ALARMS = "alarms_v1"
    }
}
