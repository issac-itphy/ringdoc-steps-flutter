package co.itphy.rdc_health

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * T4(11/6 S10 검증): 본 앱 설계처럼 알림을 미리 예약해 두고, 걸음이 늘면 꺼진 앱의 작업이 그 예약을 취소한다.
 * 정확한 알람 권한 없이 쓸 수 있는 부정확 알람(setAndAllowWhileIdle)이라 Doze에서 얼마나 늦게 뜨는지도 잰다.
 * flutter_local_notifications의 inexactAllowWhileIdle과 같은 OS API.
 * [alarmClock]이면 본 앱(notification_manager.dart의 AndroidScheduleMode.alarmClock)과 같은 setAlarmClock을 쓴다.
 * shortcut: 예약은 한 번에 하나, 정식화(C2) 때 본 앱의 예약 경로로 옮김
 */
internal object HealthSpikeAlarm {
    private const val PLANNED_AT_KEY = "alarm_planned_at"

    /** 정확한 알람 권한이 없어 alarmClock 예약을 못 하면 false. */
    fun schedule(context: Context, minutes: Int, alarmClock: Boolean = false): Boolean {
        val plannedAt = System.currentTimeMillis() + minutes * 60_000L
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        if (alarmClock) {
            // 플러그인 checkCanScheduleExactAlarms와 같은 조건. 권한 없이 부르면 SecurityException
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                HealthSpikeLog.append(context, "alarm_clock_denied", mapOf("sdk" to Build.VERSION.SDK_INT))
                return false
            }
            alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(plannedAt, null), pendingIntent(context))
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, plannedAt, pendingIntent(context))
        }
        prefs(context).edit().putLong(PLANNED_AT_KEY, plannedAt).commit()
        HealthSpikeLog.append(
            context, "notification_scheduled",
            mapOf("plannedAt" to plannedAt, "minutes" to minutes, "mode" to if (alarmClock) "alarmClock" else "inexact"),
        )
        return true
    }

    /** 예약이 있으면 취소하고 true. 걸음이 늘었을 때 HealthSpikeNotifier가 부른다. */
    fun cancelIfPending(context: Context, source: String): Boolean {
        val plannedAt = prefs(context).getLong(PLANNED_AT_KEY, 0L).takeIf { it > 0 } ?: return false
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent(context))
        prefs(context).edit().remove(PLANNED_AT_KEY).commit()
        HealthSpikeLog.append(
            context, "notification_cancelled",
            mapOf("plannedAt" to plannedAt, "source" to source, "beforeSec" to (plannedAt - System.currentTimeMillis()) / 1000),
        )
        return true
    }

    internal fun fired(context: Context) {
        val plannedAt = prefs(context).getLong(PLANNED_AT_KEY, 0L)
        prefs(context).edit().remove(PLANNED_AT_KEY).commit()
        HealthSpikeNotifier.notifyScheduled(context)
        HealthSpikeLog.append(
            context, "scheduled_notification_fired",
            mapOf("plannedAt" to plannedAt, "delaySec" to (System.currentTimeMillis() - plannedAt) / 1000),
        )
    }

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 0, Intent(context, HealthSpikeAlarmReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun prefs(context: Context) = context.getSharedPreferences(RdcHealthPlugin.PREFS, Context.MODE_PRIVATE)
}

class HealthSpikeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = HealthSpikeAlarm.fired(context.applicationContext)
}
