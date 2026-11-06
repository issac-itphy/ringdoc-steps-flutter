package co.itphy.rdc_health

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.fitness.FitnessLocal
import com.google.android.gms.fitness.LocalRecordingClient
import com.google.android.gms.fitness.data.LocalDataType
import com.google.android.gms.fitness.request.LocalDataReadRequest
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.tasks.Tasks
import java.util.concurrent.TimeUnit

/**
 * 11/6 원안 경로 측정(S7b B안): 구현 설계의 Android 신호인 활동 전환 API와 Recording API를
 * 앱이 꺼지고 화면이 꺼진 상태에서 얼마나 늦게, 어떤 단위로 주는지 잰다.
 * shortcut: 권한은 adb로 허용하고 앱이 켜질 때마다 구독과 등록을 다시 건다, 정식화(G1) 때 동의 흐름과 modules/motion으로 옮김
 */
internal object HealthSpikeMotion {
    fun ensureStarted(context: Context) {
        if (context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED) {
            HealthSpikeLog.append(context, "motion_no_permission", emptyMap())
            return
        }
        val gms = GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(context, LocalRecordingClient.LOCAL_RECORDING_CLIENT_MIN_VERSION_CODE)
        FitnessLocal.getLocalRecordingClient(context).subscribe(LocalDataType.TYPE_STEP_COUNT_DELTA)
            .addOnSuccessListener { HealthSpikeLog.append(context, "recording_subscribed", mapOf("gmsStatus" to gms)) }
            .addOnFailureListener { HealthSpikeLog.append(context, "recording_error", mapOf("gmsStatus" to gms, "message" to it.message)) }

        val transitions = listOf(DetectedActivity.WALKING, DetectedActivity.RUNNING, DetectedActivity.STILL).flatMap { type ->
            listOf(ActivityTransition.ACTIVITY_TRANSITION_ENTER, ActivityTransition.ACTIVITY_TRANSITION_EXIT).map {
                ActivityTransition.Builder().setActivityType(type).setActivityTransition(it).build()
            }
        }
        ActivityRecognition.getClient(context)
            .requestActivityTransitionUpdates(ActivityTransitionRequest(transitions), pendingIntent(context))
            .addOnSuccessListener { HealthSpikeLog.append(context, "transition_registered", emptyMap()) }
            .addOnFailureListener { HealthSpikeLog.append(context, "transition_error", mapOf("message" to it.message)) }
    }

    /** 지난 [minutes]분을 5분 칸으로 읽어 걸음이 있는 칸만 돌려준다. 주기 작업에서 부르므로 기다려서 받는다. */
    fun readRecent(context: Context, minutes: Long = 90): List<Map<String, Any?>> {
        val end = System.currentTimeMillis()
        val request = LocalDataReadRequest.Builder()
            .aggregate(LocalDataType.TYPE_STEP_COUNT_DELTA)
            .bucketByTime(5, TimeUnit.MINUTES)
            .setTimeRange(end - minutes * 60_000, end, TimeUnit.MILLISECONDS)
            .build()
        val response = Tasks.await(FitnessLocal.getLocalRecordingClient(context).readData(request), 20, TimeUnit.SECONDS)
        return response.buckets.flatMap { it.dataSets }.flatMap { it.dataPoints }.mapNotNull { point ->
            val steps = point.dataType.fields.sumOf { point.getValue(it).asInt() }
            if (steps == 0) null else mapOf(
                "start" to point.getStartTime(TimeUnit.MILLISECONDS),
                "end" to point.getEndTime(TimeUnit.MILLISECONDS),
                "steps" to steps,
            )
        }
    }

    // Play 서비스가 결과를 채워 넣어야 해서 FLAG_MUTABLE. 명시적 컴포넌트라 다른 앱이 가로채지 못함
    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 1, Intent(context, HealthSpikeMotionReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
    )
}

class HealthSpikeMotionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // 다른 앱이 보낸 가짜 전환을 거른다(구현 설계 보안 표)
        if (!ActivityTransitionResult.hasResult(intent)) return
        val now = System.currentTimeMillis()
        val nowNanos = SystemClock.elapsedRealtimeNanos()
        val events = ActivityTransitionResult.extractResult(intent)?.transitionEvents.orEmpty().map {
            val at = now - (nowNanos - it.elapsedRealTimeNanos) / 1_000_000
            mapOf("activity" to it.activityType, "transition" to it.transitionType, "at" to at, "delaySec" to (now - at) / 1000)
        }
        HealthSpikeLog.append(context.applicationContext, "transition_received", mapOf("events" to events))
    }
}
