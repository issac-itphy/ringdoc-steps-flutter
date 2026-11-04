package co.itphy.rdc_health

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
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
import java.time.Instant
import java.time.ZoneId

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

    // 결정: registerForActivityResult 대신 플러그인 결과 콜백으로 받는다. 앱의 MainActivity(FlutterActivity)를 바꾸지 않아도 됨
    private val permissionContract by lazy { PermissionController.createRequestPermissionResultContract() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "rdc_health")
        channel.setMethodCallHandler(this)
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
                result.success(null)
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

    private companion object {
        const val REQUEST_CODE = 0x5254
        val PERMISSIONS = setOf(
            HealthPermission.getReadPermission(StepsRecord::class),
            HealthPermission.getWritePermission(StepsRecord::class),
        )
    }
}
