package co.itphy.rdc_health

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.changes.UpsertionChange
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * 앱이 꺼져 있어도 주기적으로 새 걸음을 읽어 기록 파일에 남긴다. Flutter 엔진 없이 네이티브로만 돈다.
 * iOS 백그라운드 전달에 해당하는 Android 경로(S9e).
 */
class HealthSpikeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        val prefs = context.getSharedPreferences(RdcHealthPlugin.PREFS, Context.MODE_PRIVATE)
        return try {
            val client = HealthConnectClient.getOrCreate(context)
            // 결정: 화면 쪽 폴링과 토큰을 따로 써서 서로의 변경 내역을 가로채지 않게 한다
            var token = prefs.getString(RdcHealthPlugin.WORKER_TOKEN_KEY, null) ?: newToken(client)
            val now = Instant.now()
            val samples = mutableListOf<Map<String, Any?>>()
            do {
                val response = client.getChanges(token)
                if (response.changesTokenExpired) {
                    token = newToken(client)
                    break
                }
                response.changes.filterIsInstance<UpsertionChange>()
                    .mapNotNull { it.record as? StepsRecord }
                    .mapTo(samples) { record ->
                        mapOf(
                            "uuid" to record.metadata.id,
                            "start" to record.startTime.toEpochMilli(),
                            "end" to record.endTime.toEpochMilli(),
                            "count" to record.count,
                            "sourceBundleId" to record.metadata.dataOrigin.packageName,
                            "deviceType" to record.metadata.device?.type,
                            "delaySec" to now.epochSecond - record.endTime.epochSecond,
                        )
                    }
                token = response.nextChangesToken
            } while (response.hasMore)
            prefs.edit().putString(RdcHealthPlugin.WORKER_TOKEN_KEY, token).apply()
            // 변화가 없는 실행에도 오늘 합계를 남겨, 기록만 보고 쌓이는지 알 수 있게 한다
            val startOfDay = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant()
            val todayTotal = client.readRecords(
                ReadRecordsRequest(StepsRecord::class, TimeRangeFilter.between(startOfDay, now))
            ).records.sumOf { it.count }
            HealthSpikeLog.append(
                context, "worker_fired",
                mapOf("newSamples" to samples.size, "todayTotal" to todayTotal, "samples" to samples),
            )
            // S9g 1단계: 꺼진 앱의 작업이 로컬 알림을 띄울 수 있는지. 직전 실행보다 걸음이 늘었을 때만
            val previousTotal = prefs.getLong(RdcHealthPlugin.LAST_TOTAL_KEY, -1L)
            prefs.edit().putLong(RdcHealthPlugin.LAST_TOTAL_KEY, todayTotal).apply()
            if (previousTotal in 0 until todayTotal) {
                notify(context, todayTotal, todayTotal - previousTotal)
                HealthSpikeLog.append(context, "notification_posted", mapOf("todayTotal" to todayTotal, "diff" to todayTotal - previousTotal))
            }
            Result.success()
        } catch (e: Exception) {
            // 권한 해제, 잠금 상태 저장소 등. 다음 주기에 다시 시도하도록 실패로 남기지 않는다
            runCatching {
                HealthSpikeLog.append(context, "worker_error", mapOf("type" to e.javaClass.simpleName, "message" to e.message))
            }
            Result.success()
        }
    }

    private suspend fun newToken(client: HealthConnectClient): String =
        client.getChangesToken(ChangesTokenRequest(setOf(StepsRecord::class)))

    /** 탭하면 샘플 앱 첫 화면. Android 13 이상의 알림 권한(POST_NOTIFICATIONS)은 스파이크 범위 밖(S10은 Android 12). */
    private fun notify(context: Context, total: Long, diff: Long) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "걸음 시험", NotificationManager.IMPORTANCE_DEFAULT),
        )
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val tap = PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("걸음 +%,d".format(diff))
            .setContentText("오늘 %,d보. 꺼진 앱의 주기 작업이 띄운 알림".format(total))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    private companion object {
        const val CHANNEL = "rdc_health_spike"
        const val NOTIFICATION_ID = 0x5254
    }
}
