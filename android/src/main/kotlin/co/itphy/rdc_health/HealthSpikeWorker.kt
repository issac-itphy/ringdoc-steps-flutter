package co.itphy.rdc_health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.changes.UpsertionChange
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import java.time.Instant

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
            val todayTotal = HealthSpikeNotifier.todayTotal(client, now)
            HealthSpikeLog.append(
                context, "worker_fired",
                mapOf("newSamples" to samples.size, "todayTotal" to todayTotal, "samples" to samples),
            )
            HealthSpikeNotifier.onTotal(context, todayTotal, "worker")
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
}
