package co.itphy.rdc_health

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.fitness.LocalRecordingClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/** 8개 함수 API의 Android 구현. 걸음의 주 출처는 Recording API, 보조는 활동 전환과 Health Connect. */
class RdcHealthPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissions: Result? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // 결정: registerForActivityResult 대신 플러그인 결과 콜백으로 받는다. 앱의 MainActivity(FlutterActivity)를 바꾸지 않아도 됨
    private val permissionContract by lazy { PermissionController.createRequestPermissionResultContract() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "rdc_health")
        channel.setMethodCallHandler(this)
        // 결정: 켜져 있으면 엔진이 붙을 때(앱 시작, 헤드리스 포함) 전환 등록과 주기 작업을 다시 건다. 둘 다 멱등이라 Play 서비스가 등록을 잃었어도 복구된다
        val app = binding.applicationContext
        if (Store.enabled(app)) {
            WakeFlow.schedulePeriodic(app)
            // 결정: Recording API 구독도 멱등이라 전환 등록과 같이 다시 건다(enable 때 한 번만 걸면 Play 서비스가 잃었을 때 복구 안 됨)
            scope.launch(Dispatchers.IO) {
                Transitions.awaitQuietly { Transitions.register(app) }
                Transitions.awaitQuietly { Transitions.subscribe(app) }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val c = context ?: return result.error("no_context", "플러그인이 엔진에 붙어 있지 않습니다", null)
        when (call.method) {
            "availability" -> result.success(availability(c))
            "requestPermissions" -> requestPermissions(c, result)
            "enable" -> {
                val userId = call.argument<String>("userId") ?: return badArgs(result, "userId가 필요합니다")
                scope.launch {
                    // 결정: enable과 disable은 한 뮤텍스로 직렬화하고, 등록 단계마다 enabled를 다시 본다. 늦게 끝난 enable이 disable 뒤에 등록을 되살리지 않게(프라이버시)
                    lifecycle.withLock {
                        Store.enable(c, userId)
                        withContext(Dispatchers.IO) {
                            if (Store.enabled(c)) Transitions.awaitQuietly { Transitions.register(c) }
                            if (Store.enabled(c)) Transitions.awaitQuietly { Transitions.subscribe(c) }
                        }
                        if (Store.enabled(c)) WakeFlow.schedulePeriodic(c)
                    }
                    result.success(null)
                }
            }
            "setActive" -> {
                // 결정: 플래그만 저장한다. 등록과 주기 작업은 그대로 두고, 비활성이면 기록만 멈추며 Dart 핸들러는 계속 돈다
                val active = call.argument<Boolean>("active") ?: return badArgs(result, "active가 필요합니다")
                Store.setActive(c, active)
                result.success(null)
            }
            "disable" -> scope.launch {
                lifecycle.withLock {
                    // 결정: 먼저 enabled를 내려 진행 중인 enable이 더 등록하지 못하게 한다. 각 해제 실패는 무시한다(멱등)
                    Store.clearAll(c)
                    withContext(Dispatchers.IO) {
                        Transitions.awaitQuietly { Transitions.unregister(c) }
                        Transitions.awaitQuietly { Transitions.unsubscribe(c) }
                    }
                    try {
                        WakeFlow.cancelAll(c)
                    } catch (_: Exception) {
                    }
                }
                result.success(null)
            }
            "setBackgroundHandler" -> {
                val dispatcher = call.argument<Number>("dispatcherHandle")?.toLong()
                val handler = call.argument<Number>("handlerHandle")?.toLong()
                if (dispatcher == null || handler == null) return badArgs(result, "dispatcherHandle, handlerHandle가 필요합니다")
                Store.setHandles(c, dispatcher, handler)
                result.success(null)
            }
            "moveSegments" -> {
                val (from, to) = range(call) ?: return badArgs(result, "from, to(ms)가 필요합니다")
                scope.launch { result.success(withContext(Dispatchers.IO) { moveSegments(c, from, to) }) }
            }
            "hourlySteps" -> {
                val (from, to) = range(call) ?: return badArgs(result, "from, to(ms)가 필요합니다")
                scope.launch { result.success(withContext(Dispatchers.IO) { hourlySteps(c, from, to) }) }
            }
            else -> result.notImplemented()
        }
    }

    private fun badArgs(result: Result, message: String) = result.error("bad_args", message, null)

    private fun range(call: MethodCall): Pair<Long, Long>? {
        val from = call.argument<Number>("from")?.toLong() ?: return null
        val to = call.argument<Number>("to")?.toLong() ?: return null
        return from to to
    }

    // 결정: 가용성은 Recording API를 줄 Play 서비스로만 정한다. Health Connect 유무는 보조 신호라 영향 없음
    private fun availability(c: Context): String =
        when (GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(c, LocalRecordingClient.LOCAL_RECORDING_CLIENT_MIN_VERSION_CODE)) {
            ConnectionResult.SUCCESS -> "available"
            ConnectionResult.SERVICE_VERSION_UPDATE_REQUIRED,
            ConnectionResult.SERVICE_UPDATING,
            ConnectionResult.SERVICE_DISABLED -> "needsInstall"
            else -> "unsupported"
        }

    /** 소스마다 실패(권한 없음, 서비스 없음)는 삼키고 가진 것만 합친다. */
    private suspend fun moveSegments(c: Context, from: Long, to: Long): List<Map<String, Any>> {
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val walking = try { Segments.walking(Store.transitions(c), from, to, now) } catch (_: Exception) { emptyList() }
        val recording = try {
            Segments.recording(RecordingReader.buckets(c, from, to, SEGMENT_MINUTES, TimeUnit.MINUTES))
        } catch (_: Exception) { emptyList() }
        val hc = try { Segments.healthConnect(Store.totals(c), from, to, zone) } catch (_: Exception) { emptyList() }
        return (walking + recording + hc).sortedBy { it.start }.map { it.toMap() }
    }

    private fun hourlySteps(c: Context, from: Long, to: Long): List<Map<String, Any>> {
        // 결정: Recording API 보관은 10일이라 그 앞은 칸을 만들지 않는다(칸 없음 = 읽을 수 없는 범위)
        val hours = Segments.hourStarts(RecordingReader.clampFrom(from, System.currentTimeMillis()), to, ZoneId.systemDefault())
        if (hours.isEmpty()) return emptyList()
        // 결정: Recording API 오류는 빈 목록으로 돌려준다(iOS와 같음. 0보와 "읽지 못함"을 호스트가 구분)
        // shortcut: 칸 기준이 읽기 시작 시각이라 정각으로 맞춰 읽는다. 일광절약 전환일의 25/23시간은 따로 다루지 않음
        val buckets = try {
            RecordingReader.buckets(c, hours.first(), to, 1, TimeUnit.HOURS)
        } catch (_: Exception) { return emptyList() }
        return Segments.fillHours(hours, buckets)
    }

    // ---- 권한 ----

    private fun activityRecognitionGranted(c: Context) =
        Build.VERSION.SDK_INT < 29 || c.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED

    /**
     * 결정: 활동 인식(API 29 이상 런타임 권한)을 먼저 묻고, Health Connect가 있으면 걸음 읽기와 백그라운드 읽기를 이어서 묻는다.
     * 반환값은 활동 인식 허용 여부뿐이다. Health Connect 권한은 선택이라 거부돼도 true.
     */
    private fun requestPermissions(c: Context, result: Result) {
        val activity = activityBinding?.activity
            ?: return result.error("no_activity", "권한 화면을 띄울 Activity가 없습니다", null)
        if (pendingPermissions != null) return result.error("in_progress", "이미 권한을 요청하는 중입니다", null)
        pendingPermissions = result
        if (activityRecognitionGranted(c)) {
            requestHealthConnect(activity)
        } else {
            activity.requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), REQUEST_ACTIVITY)
        }
    }

    private fun requestHealthConnect(activity: Activity) {
        scope.launch {
            try {
                if (HealthConnectSteps.isAvailable(activity)) {
                    val client = HealthConnectClient.getOrCreate(activity)
                    val wanted = mutableSetOf(HealthPermission.getReadPermission(StepsRecord::class))
                    if (client.features.getFeatureStatus(HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND) ==
                        HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
                    ) wanted += BACKGROUND_READ
                    if (!client.permissionController.getGrantedPermissions().containsAll(wanted)) {
                        // Android 14부터 건강 권한은 일반 런타임 권한이다. 계약이 만드는 REQUEST_PERMISSIONS 인텐트는
                        // registerForActivityResult 전용이라 직접 띄우면 실패한다(2026-11-04 에뮬레이터 확인)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            activity.requestPermissions(wanted.toTypedArray(), REQUEST_HEALTH)
                        } else {
                            activity.startActivityForResult(permissionContract.createIntent(activity, wanted), REQUEST_HEALTH)
                        }
                        return@launch
                    }
                }
            } catch (_: Exception) {
                // 보조 권한 단계의 실패는 결과에 영향을 주지 않는다
            }
            finishPermissions()
        }
    }

    private fun finishPermissions() {
        val c = context
        pendingPermissions?.success(c != null && activityRecognitionGranted(c))
        pendingPermissions = null
    }

    /** Android 13 이하: Health Connect 앱의 권한 화면 결과 */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_HEALTH) return false
        finishPermissions()
        return true
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        when (requestCode) {
            REQUEST_ACTIVITY -> activityBinding?.activity?.let(::requestHealthConnect) ?: finishPermissions()
            REQUEST_HEALTH -> finishPermissions()
            else -> return false
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
        context = null
    }

    private companion object {
        val lifecycle = Mutex()
        const val REQUEST_ACTIVITY = 0x5254
        const val REQUEST_HEALTH = 0x5255
        const val BACKGROUND_READ = "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"
    }
}
