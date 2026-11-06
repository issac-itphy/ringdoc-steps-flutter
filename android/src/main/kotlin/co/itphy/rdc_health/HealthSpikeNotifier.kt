package co.itphy.rdc_health

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * S9g/S9h: 오늘 걸음 합계가 직전 확인보다 늘었으면 로컬 알림을 띄운다.
 * 주기 작업(앱이 꺼져 있을 때)과 10초 폴링(앱이 켜져 있을 때)이 같은 직전 합계를 써서 같은 증가로 두 번 알리지 않는다.
 */
internal object HealthSpikeNotifier {
    private const val CHANNEL = "rdc_health_spike"
    private const val NOTIFICATION_ID = 0x5254

    suspend fun todayTotal(client: HealthConnectClient, now: Instant = Instant.now()): Long {
        val startOfDay = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant()
        return client.readRecords(ReadRecordsRequest(StepsRecord::class, TimeRangeFilter.between(startOfDay, now)))
            .records.sumOf { it.count }
    }

    /** 직전 합계가 없으면(설치 뒤 첫 확인) 기준값만 잡는다. 날짜가 바뀌어 줄면 알리지 않는다. */
    fun increase(previous: Long?, total: Long): Long? = previous?.let { total - it }?.takeIf { it > 0 }

    /** source는 "worker" 또는 "observer". 두 경로가 동시에 돌 수 있어 비교와 저장을 묶는다. */
    @Synchronized
    fun onTotal(context: Context, total: Long, source: String) {
        val prefs = context.getSharedPreferences(RdcHealthPlugin.PREFS, Context.MODE_PRIVATE)
        val previous = prefs.getLong(RdcHealthPlugin.LAST_TOTAL_KEY, -1L).takeIf { it >= 0 }
        prefs.edit().putLong(RdcHealthPlugin.LAST_TOTAL_KEY, total).commit()
        val diff = increase(previous, total) ?: return
        // T4: 예약 알림이 있으면 바로 띄우지 않고 그 예약을 취소한다(본 앱의 "움직이면 취소")
        if (HealthSpikeAlarm.cancelIfPending(context, source)) return
        notify(context, total, diff, source)
        HealthSpikeLog.append(context, "notification_posted", mapOf("diff" to diff, "total" to total, "source" to source))
    }

    private fun notify(context: Context, total: Long, diff: Long, source: String) {
        val by = if (source == "observer") "앱이 켜진 상태의 10초 확인" else "꺼진 앱의 주기 작업"
        post(context, "걸음 +%,d".format(diff), "오늘 %,d보. %s이 띄운 알림".format(total, by))
    }

    /** T4: 예약해 둔 알림이 취소되지 않고 시간이 되어 뜬 경우. */
    fun notifyScheduled(context: Context) =
        post(context, "예약 알림", "예약한 시각까지 걸음 증가가 없어 그대로 떴습니다(취소 안 됨)")

    /** 탭하면 샘플 앱 첫 화면. Android 13 이상의 알림 권한(POST_NOTIFICATIONS)은 스파이크 범위 밖(S10은 Android 12). */
    private fun post(context: Context, title: String, text: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "걸음 시험", NotificationManager.IMPORTANCE_DEFAULT))
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val tap = PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }
}
