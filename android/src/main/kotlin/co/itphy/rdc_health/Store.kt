package co.itphy.rdc_health

import android.content.Context
import java.io.File
import java.time.Instant
import java.time.ZoneId

/** 수집 스위치(SharedPreferences)와 플러그인 파일. 모든 키는 `rdc_health` 접두사. */
internal object Store {
    private const val PREFS = "rdc_health"
    private const val ENABLED = "rdc_health.enabled"
    private const val ACTIVE = "rdc_health.active"
    private const val USER_ID = "rdc_health.userId"
    private const val DISPATCHER = "rdc_health.dispatcherHandle"
    private const val HANDLER = "rdc_health.handlerHandle"
    private const val TRANSITIONS = "rdc_health_transitions.txt"
    private const val TOTALS = "rdc_health_totals.txt"

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun enabled(c: Context) = prefs(c).getBoolean(ENABLED, false)
    fun active(c: Context) = prefs(c).getBoolean(ACTIVE, false)

    fun enable(c: Context, userId: String) =
        prefs(c).edit().putBoolean(ENABLED, true).putBoolean(ACTIVE, true).putString(USER_ID, userId).apply()

    fun setActive(c: Context, active: Boolean) = prefs(c).edit().putBoolean(ACTIVE, active).apply()

    fun setHandles(c: Context, dispatcher: Long, handler: Long) =
        prefs(c).edit().putLong(DISPATCHER, dispatcher).putLong(HANDLER, handler).apply()

    /** (dispatcher, handler). 등록 전이면 null */
    fun handles(c: Context): Pair<Long, Long>? {
        val p = prefs(c)
        return if (p.contains(DISPATCHER) && p.contains(HANDLER)) p.getLong(DISPATCHER, 0) to p.getLong(HANDLER, 0) else null
    }

    fun clearAll(c: Context) {
        synchronized(this) {
            prefs(c).edit().clear().apply()
            File(c.filesDir, TRANSITIONS).delete()
            File(c.filesDir, TOTALS).delete()
        }
    }

    /** 걷기 전환(true=시작). */
    fun addTransition(c: Context, at: Long, enter: Boolean) = append(c, TRANSITIONS, at, if (enter) 1 else 0)

    fun transitions(c: Context): List<Pair<Long, Boolean>> = read(c, TRANSITIONS).map { it.first to (it.second == 1L) }

    /** Health Connect 오늘 합계 점(시각, 합계). */
    fun addTotal(c: Context, at: Long, total: Long) = append(c, TOTALS, at, total)

    fun totals(c: Context): List<Pair<Long, Long>> = read(c, TOTALS)

    // 결정: 어제와 오늘 것만 남긴다. 그보다 오래된 줄은 쓸 때마다 걸러 낸다(걸음 시각 기록을 오래 두지 않음)
    private fun append(c: Context, name: String, a: Long, b: Long) = synchronized(this) {
        val keep = read(c, name) + (a to b)
        File(c.filesDir, name).writeText(keep.joinToString("") { "${it.first},${it.second}\n" })
    }

    private fun read(c: Context, name: String): List<Pair<Long, Long>> = synchronized(this) {
        val file = File(c.filesDir, name)
        if (!file.exists()) return emptyList()
        val zone = ZoneId.systemDefault()
        val since = Instant.now().atZone(zone).toLocalDate().minusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        file.readLines().mapNotNull { line ->
            val p = line.split(',')
            val a = p.getOrNull(0)?.toLongOrNull()
            val b = p.getOrNull(1)?.toLongOrNull()
            if (a != null && b != null && a >= since) a to b else null
        }
    }
}
