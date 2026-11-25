package co.itphy.rdc_health

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** 헤드리스 엔진을 띄워 Dart 핸들러를 한 번 실행하고 끝나면 끈다. */
internal object BackgroundRunner {
    // 결정: 핸들러 응답을 60초까지 기다리고 넘으면 엔진을 끈다(작업 제한 시간 안, 배터리 보호)
    private const val TIMEOUT_MS = 60_000L

    suspend fun run(c: Context, dispatcher: Long, handler: Long) = withContext(Dispatchers.Main) {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(c)
        loader.ensureInitializationComplete(c, null)
        val info = FlutterCallbackInformation.lookupCallbackInformation(dispatcher) ?: return@withContext
        val engine = FlutterEngine(c)
        try {
            val done = CompletableDeferred<Unit>()
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "rdc_health/background")
            channel.setMethodCallHandler { call, reply ->
                if (call.method != "ready") return@setMethodCallHandler reply.notImplemented()
                reply.success(null)
                // `run`은 Dart가 ready를 보낸 뒤에만 보낸다. 성공/오류 어느 응답이든 끝난 것으로 본다
                channel.invokeMethod("run", mapOf("handlerHandle" to handler), object : MethodChannel.Result {
                    override fun success(result: Any?) { done.complete(Unit) }
                    override fun error(code: String, message: String?, details: Any?) { done.complete(Unit) }
                    override fun notImplemented() { done.complete(Unit) }
                })
            }
            engine.dartExecutor.executeDartCallback(DartExecutor.DartCallback(c.assets, loader.findAppBundlePath(), info))
            withTimeoutOrNull(TIMEOUT_MS) { done.await() }
        } finally {
            engine.destroy()
        }
    }
}
