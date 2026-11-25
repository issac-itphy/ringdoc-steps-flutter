package co.itphy.rdc_health

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import com.google.android.gms.fitness.FitnessLocal
import com.google.android.gms.fitness.data.LocalDataType
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import java.util.concurrent.TimeUnit

/** Play 서비스 쪽 등록: 활동 전환(걷기 시작/끝)과 Recording API 걸음 구독. */
internal object Transitions {
    // Play 서비스가 결과를 채워 넣어야 해서 FLAG_MUTABLE. 명시적 컴포넌트라 다른 앱이 가로채지 못함
    private fun pendingIntent(c: Context): PendingIntent = PendingIntent.getBroadcast(
        c, 1, Intent(c, TransitionReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
    )

    fun register(c: Context): Task<Void> {
        val list = listOf(ActivityTransition.ACTIVITY_TRANSITION_ENTER, ActivityTransition.ACTIVITY_TRANSITION_EXIT).map {
            ActivityTransition.Builder().setActivityType(DetectedActivity.WALKING).setActivityTransition(it).build()
        }
        return ActivityRecognition.getClient(c).requestActivityTransitionUpdates(ActivityTransitionRequest(list), pendingIntent(c))
    }

    fun unregister(c: Context): Task<Void> = ActivityRecognition.getClient(c).removeActivityTransitionUpdates(pendingIntent(c))

    fun subscribe(c: Context): Task<Void> = FitnessLocal.getLocalRecordingClient(c).subscribe(LocalDataType.TYPE_STEP_COUNT_DELTA)

    fun unsubscribe(c: Context): Task<Void> = FitnessLocal.getLocalRecordingClient(c).unsubscribe(LocalDataType.TYPE_STEP_COUNT_DELTA)

    /** 백그라운드 스레드에서만 부른다. 실패(권한 없음, Play 서비스 없음)는 삼키고 나머지 등록을 이어 간다. */
    fun awaitQuietly(block: () -> Task<*>) {
        try {
            Tasks.await(block(), 10, TimeUnit.SECONDS)
        } catch (_: Exception) {
        }
    }
}

class TransitionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // 다른 앱이 보낸 가짜 전환을 거른다
        if (!ActivityTransitionResult.hasResult(intent)) return
        val app = context.applicationContext
        if (!Store.enabled(app)) return
        val now = System.currentTimeMillis()
        val nowNanos = SystemClock.elapsedRealtimeNanos()
        val events = ActivityTransitionResult.extractResult(intent)?.transitionEvents.orEmpty()
            .filter { it.activityType == DetectedActivity.WALKING }
        for (e in events) {
            Store.addTransition(
                app,
                now - (nowNanos - e.elapsedRealTimeNanos) / 1_000_000,
                e.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER,
            )
        }
        // 결정: 수신기는 약 10초만 산다. 여기서 Dart 엔진을 띄우지 않고 기록만 한 뒤 작업으로 넘긴다
        if (events.isNotEmpty() && Store.active(app)) WakeFlow.enqueueWake(app)
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        // 활동 전환 등록은 재부팅과 앱 업데이트로 사라진다. 알람은 호스트 앱의 flutter_local_notifications 수신기가 다시 건다
        if (!Store.enabled(app)) return
        try {
            Transitions.register(app)
        } catch (_: Exception) {
        }
        WakeFlow.schedulePeriodic(app)
    }
}
