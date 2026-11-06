package co.itphy.rdc_health

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.changes.UpsertionChange
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateGroupByDurationRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
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
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/** Android는 Health Connect로 걸음을 읽고 쓴다. */
class RdcHealthPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingAuthorization: Result? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pollJob: Job? = null
    private val changesLock = Mutex()
    private val prefs get() = context!!.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // 결정: registerForActivityResult 대신 플러그인 결과 콜백으로 받는다. 앱의 MainActivity(FlutterActivity)를 바꾸지 않아도 됨
    private val permissionContract by lazy { PermissionController.createRequestPermissionResultContract() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "rdc_health")
        channel.setMethodCallHandler(this)
        HealthSpikeLog.append(binding.applicationContext, "plugin_registered")
        // iOS bootstrap처럼, 켜 둔 적이 있으면 엔진이 붙을 때 다시 감지를 시작한다
        if (prefs.getBoolean(OBSERVING_KEY, false)) startPolling()
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${android.os.Build.VERSION.RELEASE}")
            // 결정: 스파이크에서는 iOS 메서드 이름을 그대로 쓰고, 두 플랫폼 공통 이름은 S7c에서 정한다
            "requestHealthKitAuthorization" -> requestAuthorization(result)
            "healthStepSamples" -> withClient(result) { client ->
                val from = Instant.ofEpochMilli(call.argument<Number>("from")!!.toLong())
                val to = Instant.ofEpochMilli(call.argument<Number>("to")!!.toLong())
                val response = client.readRecords(
                    ReadRecordsRequest(StepsRecord::class, TimeRangeFilter.between(from, to))
                )
                result.success(response.records.map(::toMap))
            }
            "writeTestSteps" -> withClient(result) { client ->
                // 샘플 앱 시험용(G1 정식화 때 제거)
                val count = call.argument<Number>("count")?.toLong() ?: 50L
                val end = Instant.now()
                val start = end.minusSeconds(60)
                val offset = ZoneId.systemDefault().rules.getOffset(start)
                client.insertRecords(
                    listOf(
                        StepsRecord(
                            count = count,
                            startTime = start,
                            endTime = end,
                            startZoneOffset = offset,
                            endZoneOffset = offset,
                            metadata = Metadata.manualEntry(),
                        )
                    )
                )
                // 폴링을 기다리지 않고 바로 확인해 실시간 칸에 곧장 보이게 한다
                if (prefs.getBoolean(OBSERVING_KEY, false)) deliverChanges(client)
                result.success(null)
            }
            "enableBackgroundDelivery" -> withClient(result) { client ->
                if (prefs.getString(TOKEN_KEY, null) == null) saveToken(newToken(client))
                prefs.edit().putBoolean(OBSERVING_KEY, true).apply()
                startPolling()
                HealthSpikeLog.append(context!!, "observer_registered", mapOf("pollSec" to POLL_MS / 1000))
                scheduleWorker(client)
                result.success(null)
            }
            "readLog" -> result.success(HealthSpikeLog.read(context!!))
            "appendLog" -> {
                HealthSpikeLog.append(context!!, call.argument<String>("event") ?: "unknown", call.argument<Map<String, Any?>>("detail") ?: emptyMap())
                result.success(null)
            }
            "clearLog" -> {
                HealthSpikeLog.clear(context!!)
                result.success(null)
            }
            "deviceInfo" -> deviceInfo(result)
            // S8: Health Connect 집계는 삼성 헬스 하루 기록을 시간 비율로 나누므로(T1) 시간대별 판단에는 쓸 수 없음. iOS와 같은 모양만 맞춤
            "healthStepBuckets" -> withClient(result) { client ->
                val from = Instant.ofEpochMilli(call.argument<Number>("from")!!.toLong())
                val to = Instant.ofEpochMilli(call.argument<Number>("to")!!.toLong())
                val size = Duration.ofSeconds(call.argument<Number>("sizeSec")!!.toLong())
                val rows = client.aggregateGroupByDuration(
                    AggregateGroupByDurationRequest(setOf(StepsRecord.COUNT_TOTAL), TimeRangeFilter.between(from, to), size)
                ).map {
                    mapOf("start" to it.startTime.toEpochMilli(), "end" to it.endTime.toEpochMilli(), "steps" to (it.result[StepsRecord.COUNT_TOTAL] ?: 0L).toInt())
                }
                result.success(rows)
            }
            "scheduleTestNotification" -> {
                val ctx = context ?: return result.error("no_context", "플러그인이 엔진에 붙어 있지 않습니다", null)
                HealthSpikeAlarm.schedule(ctx, call.argument<Number>("minutes")?.toInt() ?: 20)
                result.success(null)
            }
            "aggregateCheck" -> withClient(result) { client ->
                val check = aggregateCheck(client)
                HealthSpikeLog.append(context!!, "aggregate_check", check)
                result.success(check)
            }
            // CoreMotion 비교는 iOS 전용. 비교 화면이 Android에서도 열리도록 빈 값을 돌려준다
            "isStepCountingAvailable" -> result.success(false)
            "stepBuckets" -> result.success(emptyList<Any>())
            else -> result.notImplemented()
        }
    }

    private fun requestAuthorization(result: Result) {
        val activity = activityBinding?.activity
            ?: return result.error("no_activity", "권한 화면을 띄울 Activity가 없습니다", null)
        withClient(result) { client ->
            if (client.permissionController.getGrantedPermissions().containsAll(PERMISSIONS)) {
                result.success(true)
                return@withClient
            }
            pendingAuthorization = result
            try {
                // Android 14부터 건강 권한은 일반 런타임 권한이다. 계약이 만드는 REQUEST_PERMISSIONS 인텐트는
                // registerForActivityResult 전용이라 직접 띄우면 실패한다(2026-11-04 에뮬레이터 확인)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    activity.requestPermissions(PERMISSIONS.toTypedArray(), REQUEST_CODE)
                } else {
                    activity.startActivityForResult(permissionContract.createIntent(activity, PERMISSIONS), REQUEST_CODE)
                }
            } catch (e: Exception) {
                pendingAuthorization = null
                throw e
            }
        }
    }

    /** Android 13 이하: Health Connect 앱의 권한 화면 결과 */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        finishAuthorization(requestCode)

    /** Android 14 이상: 런타임 권한 결과 */
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean = finishAuthorization(requestCode)

    /** iOS와 같게 "요청 창 처리가 끝났다"를 돌려준다. 허용 여부는 조회 결과로 본다. */
    private fun finishAuthorization(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        pendingAuthorization?.success(true)
        pendingAuthorization = null
        return true
    }

    /** Health Connect를 쓸 수 없으면 오류를 돌려주고, 예외는 Flutter 오류로 바꾼다. */
    private fun withClient(result: Result, block: suspend (HealthConnectClient) -> Unit) {
        val ctx = context ?: return result.error("no_context", "플러그인이 엔진에 붙어 있지 않습니다", null)
        val status = HealthConnectClient.getSdkStatus(ctx)
        if (status != HealthConnectClient.SDK_AVAILABLE) {
            result.error("health_connect_unavailable", "Health Connect 상태 코드 $status", null)
            return
        }
        val client = HealthConnectClient.getOrCreate(ctx)
        scope.launch {
            try {
                block(client)
            } catch (e: Exception) {
                result.error(e.javaClass.simpleName, e.message, null)
            }
        }
    }

    // shortcut: 앱(엔진)이 떠 있을 때만 10초마다 변경 내역을 가져온다. 꺼져 있을 때 읽기는 S9e(WorkManager)
    private fun startPolling() {
        if (pollJob?.isActive == true) return
        val ctx = context ?: return
        if (HealthConnectClient.getSdkStatus(ctx) != HealthConnectClient.SDK_AVAILABLE) return
        val client = HealthConnectClient.getOrCreate(ctx)
        pollJob = scope.launch {
            while (isActive) {
                // 권한이 꺼졌거나 일시 오류여도 다음 주기에 다시 시도
                runCatching { deliverChanges(client) }
                delay(POLL_MS)
            }
        }
    }

    /** 변경 토큰 뒤로 새로 들어온 걸음을 Flutter로 보낸다. 폴링과 쓰기 직후 확인이 겹치지 않게 잠근다. */
    private suspend fun deliverChanges(client: HealthConnectClient) = changesLock.withLock {
        var token = prefs.getString(TOKEN_KEY, null) ?: return@withLock
        val samples = mutableListOf<Map<String, Any?>>()
        do {
            val response = client.getChanges(token)
            if (response.changesTokenExpired) {
                // shortcut: 만료(30일 미사용)되면 새 토큰부터 다시 시작해 그 사이 걸음은 놓친다, 정식화(G1) 때 마지막 읽은 시각부터 다시 읽기
                saveToken(newToken(client))
                return@withLock
            }
            response.changes.filterIsInstance<UpsertionChange>()
                .mapNotNull { it.record as? StepsRecord }
                .mapTo(samples, ::toMap)
            token = response.nextChangesToken
        } while (response.hasMore)
        saveToken(token)
        // 결정: 스파이크에서는 이 앱이 쓴 테스트 걸음도 보낸다(공식 예제는 자기 앱 기록을 거름)
        if (samples.isEmpty()) return@withLock
        channel.invokeMethod("onStepSamples", mapOf("samples" to samples))
        val now = System.currentTimeMillis()
        val todayTotal = HealthSpikeNotifier.todayTotal(client)
        HealthSpikeLog.append(
            context!!,
            "observer_fired",
            mapOf(
                "newSamples" to samples.size,
                "todayTotal" to todayTotal,
                "samples" to samples.map { it + ("delaySec" to (now - (it["end"] as Long)) / 1000) },
                "sentToDart" to true,
            ),
        )
        // S9h: 앱이 켜져 있을 때도 걸음이 늘면 알림. 주기 작업과 직전 합계를 같이 써서 중복 알림을 막는다
        HealthSpikeNotifier.onTotal(context!!, todayTotal, "observer")
    }

    /**
     * 앱이 꺼져 있을 때 읽는 주기 작업을 건다(S9e). 기기가 기능을 지원하고 백그라운드 읽기 권한이 있을 때만.
     * 결정: 스파이크 측정을 위해 WorkManager 최소 주기인 15분으로 둔다. 정식 주기는 S7b에서 배터리와 함께 정한다
     */
    private suspend fun scheduleWorker(client: HealthConnectClient) {
        val ctx = context ?: return
        val supported = client.features.getFeatureStatus(
            HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND
        ) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
        val granted = BACKGROUND_READ in client.permissionController.getGrantedPermissions()
        if (!supported || !granted) {
            HealthSpikeLog.append(ctx, "worker_unavailable", mapOf("featureSupported" to supported, "permissionGranted" to granted))
            return
        }
        WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
            WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<HealthSpikeWorker>(15, TimeUnit.MINUTES).build(),
        )
        HealthSpikeLog.append(ctx, "worker_scheduled", mapOf("intervalMin" to 15))
    }

    /** S9a 기기 확인: 제조사, Android 버전, Health Connect 상태와 기능, 삼성 헬스 설치, 허용된 권한. */
    /**
     * T1(11/6 S10 검증): 집계 API가 삼성 헬스의 하루 기록 1건을 시간 비율로 나누는지 본다.
     * 오늘 00:00~지금의 집계 합계, 1시간 단위 집계, 기록 단건을 한 번에 돌려준다.
     */
    private suspend fun aggregateCheck(client: HealthConnectClient): Map<String, Any?> {
        val zone = ZoneId.systemDefault()
        val now = Instant.now()
        val range = TimeRangeFilter.between(LocalDate.now(zone).atStartOfDay(zone).toInstant(), now)
        val total = client.aggregate(AggregateRequest(setOf(StepsRecord.COUNT_TOTAL), range))[StepsRecord.COUNT_TOTAL]
        val hourly = client.aggregateGroupByDuration(
            AggregateGroupByDurationRequest(setOf(StepsRecord.COUNT_TOTAL), range, Duration.ofHours(1))
        ).map { mapOf("start" to it.startTime.toEpochMilli(), "steps" to it.result[StepsRecord.COUNT_TOTAL]) }
        val records = client.readRecords(ReadRecordsRequest(StepsRecord::class, range)).records.map {
            mapOf(
                "start" to it.startTime.toEpochMilli(),
                "end" to it.endTime.toEpochMilli(),
                "count" to it.count,
                "source" to it.metadata.dataOrigin.packageName,
            )
        }
        return mapOf("aggregateToday" to total, "hourly" to hourly, "records" to records, "now" to now.toEpochMilli())
    }

    private fun deviceInfo(result: Result) {
        val ctx = context ?: return result.error("no_context", "플러그인이 엔진에 붙어 있지 않습니다", null)
        val status = HealthConnectClient.getSdkStatus(ctx)
        val info = mutableMapOf<String, Any?>(
            "platform" to "android",
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "release" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "healthConnect" to when (status) {
                HealthConnectClient.SDK_AVAILABLE -> "available"
                HealthConnectClient.SDK_UNAVAILABLE -> "unavailable"
                HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "update_required"
                else -> "status_$status"
            },
            // Android 13 이하는 Health Connect가 별도 앱. 14 이상은 OS 안에 있어 이 패키지가 없을 수 있다
            "healthConnectAppVersion" to packageVersion(ctx, "com.google.android.apps.healthdata"),
            "samsungHealthVersion" to packageVersion(ctx, SAMSUNG_HEALTH),
        )
        if (status != HealthConnectClient.SDK_AVAILABLE) return result.success(info)
        scope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(ctx)
                fun feature(flag: Int) = client.features.getFeatureStatus(flag) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
                info["backgroundReadSupported"] = feature(HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND)
                info["historyReadSupported"] = feature(HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY)
                info["granted"] = client.permissionController.getGrantedPermissions()
                    .map { it.removePrefix("android.permission.health.") }.sorted()
            } catch (e: Exception) {
                info["error"] = e.message
            }
            result.success(info)
        }
    }

    /** 설치돼 있으면 버전 이름, 없거나 공개 범위 밖이면 null. 매니페스트 queries에 넣은 패키지만 보인다. */
    private fun packageVersion(ctx: Context, packageName: String): String? =
        runCatching { ctx.packageManager.getPackageInfo(packageName, 0).versionName }.getOrNull()

    private suspend fun newToken(client: HealthConnectClient): String =
        client.getChangesToken(ChangesTokenRequest(setOf(StepsRecord::class)))

    private fun saveToken(token: String) = prefs.edit().putString(TOKEN_KEY, token).apply()

    private fun toMap(record: StepsRecord): Map<String, Any?> {
        val origin = record.metadata.dataOrigin.packageName
        val device = record.metadata.device
        return mapOf(
            "uuid" to record.metadata.id,
            "start" to record.startTime.toEpochMilli(),
            "end" to record.endTime.toEpochMilli(),
            "count" to record.count,
            "sourceName" to appLabel(origin),
            "sourceBundleId" to origin,
            "deviceModel" to device?.model,
            "deviceName" to device?.manufacturer,
            "deviceType" to deviceTypeName(device?.type),
        )
    }

    /** 다른 앱 이름은 패키지 공개 범위 밖이면 못 읽으므로 패키지 이름으로 대신한다. */
    private fun appLabel(packageName: String): String {
        val pm = context?.packageManager ?: return packageName
        return runCatching { pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString() }
            .getOrDefault(packageName)
    }

    private fun deviceTypeName(type: Int?): String? = when (type) {
        null -> null
        Device.TYPE_WATCH -> "watch"
        Device.TYPE_PHONE -> "phone"
        Device.TYPE_UNKNOWN -> "unknown"
        else -> "type_$type"
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

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

    internal companion object {
        const val REQUEST_CODE = 0x5254
        const val PREFS = "rdc_health_spike"
        const val OBSERVING_KEY = "observing"
        const val TOKEN_KEY = "changes_token"
        const val WORKER_TOKEN_KEY = "worker_changes_token"
        const val LAST_TOTAL_KEY = "worker_last_total"
        const val WORK_NAME = "rdc_health_spike_read"
        const val POLL_MS = 10_000L
        const val SAMSUNG_HEALTH = "com.sec.android.app.shealth"
        const val BACKGROUND_READ = "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"

        // 과거 기록(30일 넘게) 권한은 S9f 범위 확인용. 권한 화면에서 끄고 켜며 비교한다
        const val HISTORY_READ = "android.permission.health.READ_HEALTH_DATA_HISTORY"
        val PERMISSIONS = setOf(
            HealthPermission.getReadPermission(StepsRecord::class),
            HealthPermission.getWritePermission(StepsRecord::class),
            BACKGROUND_READ,
            HISTORY_READ,
        )
    }
}
