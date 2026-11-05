package co.itphy.rdc_health

import android.app.ActivityManager
import android.content.Context
import android.os.UserManager
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 스파이크 전용 기기 안 기록. iOS HealthSpikeLog와 같은 형식으로 filesDir/rdc_health_spike/log.jsonl에 한 줄에 JSON 하나.
 * shortcut: 크기 제한과 정리 없음, 정식화(G1) 때 디버그 기록(C12)으로 바꿈
 */
internal object HealthSpikeLog {
    private fun file(context: Context) =
        File(context.filesDir, "rdc_health_spike/log.jsonl").apply { parentFile?.mkdirs() }

    /** appState는 앱 프로세스가 화면 앞에 있는지, protectedData는 재시작 뒤 첫 잠금 해제가 됐는지(암호화 저장소 사용 가능). */
    @Synchronized
    fun append(context: Context, event: String, detail: Map<String, Any?> = emptyMap()) {
        val entry = JSONObject()
            .put("at", System.currentTimeMillis())
            .put("event", event)
            .put("appState", appState())
            .put("protectedData", context.getSystemService(UserManager::class.java)?.isUserUnlocked ?: true)
            .put("detail", JSONObject.wrap(detail))
        file(context).appendText("$entry\n")
    }

    fun read(context: Context): List<Map<String, Any?>> {
        val file = file(context)
        if (!file.exists()) return emptyList()
        return file.readLines().mapNotNull { line -> runCatching { toMap(JSONObject(line)) }.getOrNull() }
    }

    fun clear(context: Context) {
        file(context).delete()
    }

    private fun appState(): String {
        val info = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(info)
        return if (info.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) "active" else "background"
    }

    private fun toMap(json: JSONObject): Map<String, Any?> =
        json.keys().asSequence().associateWith { unwrap(json.get(it)) }

    private fun unwrap(value: Any?): Any? = when (value) {
        is JSONObject -> toMap(value)
        is JSONArray -> (0 until value.length()).map { unwrap(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }
}
