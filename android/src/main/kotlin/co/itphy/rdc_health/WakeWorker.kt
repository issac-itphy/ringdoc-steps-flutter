package co.itphy.rdc_health

import android.content.Context
import android.os.Build
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import java.util.concurrent.TimeUnit

/** 주기 작업과 전환 직후 작업이 같이 쓴다. 항상 성공으로 끝나 재시도 폭주를 막는다. */
class WakeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        WakeFlow.run(applicationContext)
        return Result.success()
    }
}

internal object WakeFlow {
    private const val PERIODIC = "rdc_health_periodic"
    private const val WAKE = "rdc_health_wake"

    // 결정: WorkManager 최소 주기 15분. 전환 신호를 놓쳤을 때의 안전망
    fun schedulePeriodic(c: Context) {
        WorkManager.getInstance(c).enqueueUniquePeriodicWork(
            PERIODIC, ExistingPeriodicWorkPolicy.KEEP, PeriodicWorkRequestBuilder<WakeWorker>(15, TimeUnit.MINUTES).build(),
        )
    }

    fun enqueueWake(c: Context) {
        val request = OneTimeWorkRequestBuilder<WakeWorker>().apply {
            // 결정: 신속 작업은 API 31 미만에서 포그라운드 서비스 알림이 필요해 31 이상에서만 쓴다. 그 아래는 일반 작업
            if (Build.VERSION.SDK_INT >= 31) setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        }.build()
        WorkManager.getInstance(c).enqueueUniqueWork(WAKE, ExistingWorkPolicy.KEEP, request)
    }

    fun cancelAll(c: Context) {
        WorkManager.getInstance(c).cancelUniqueWork(PERIODIC)
        WorkManager.getInstance(c).cancelUniqueWork(WAKE)
    }

    // 결정: 주기 작업과 전환 작업은 이름이 달라 동시에 돌 수 있다. 헤드리스 엔진 둘을 막으려고 프로세스 전체에서 하나만 돌린다
    private val running = Mutex()

    suspend fun run(c: Context) {
        // 결정: 이미 도는 쪽이 현재 데이터를 판단하므로 기다리지 않고 건너뛴다(성공으로 끝)
        if (!running.tryLock()) return
        try {
            runLocked(c)
        } finally {
            running.unlock()
        }
    }

    private suspend fun runLocked(c: Context) {
        if (!Store.enabled(c)) return
        // 결정: Dart 핸들러는 켜져 있으면 비활성이어도 부른다(호스트가 로그아웃 14일 뒤 disable 같은 판단을 함). 비활성이면 기록(합계 저장)만 멈춘다
        if (Store.active(c)) quietly { if (HealthConnectSteps.isAvailable(c)) HealthConnectSteps.recordTotal(c) }
        val handles = Store.handles(c)
        if (handles != null) quietly { BackgroundRunner.run(c, handles.first, handles.second) }
    }

    private suspend fun quietly(block: suspend () -> Unit) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
    }
}
