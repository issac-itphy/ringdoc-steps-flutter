package co.itphy.rdc_health

import android.app.ActivityManager
import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.os.UserManager
import android.provider.MediaStore
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.ZoneId

/**
 * 스파이크 전용 기기 안 기록. iOS HealthSpikeLog와 같은 형식으로 filesDir/rdc_health_spike/log.jsonl에 한 줄에 JSON 하나.
 * shortcut: 크기 제한과 정리 없음, 정식화(G1) 때 디버그 기록(C12)으로 바꿈
 */
internal object HealthSpikeLog {
    private const val DOWNLOAD_DIR = "Download/rdc_health_spike/"
    private const val DOWNLOAD_NAME = "log.txt" // 내 파일 앱이 .jsonl은 못 열어서
    private val READ_EVENTS = setOf("worker_fired", "observer_fired")

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
        runCatching { mirrorToDownloads(context) }
    }

    /**
     * 디버그 빌드에서만 Downloads/rdc_health_spike/log.txt에 읽기 쉬운 한 줄 요약으로 통째로 다시 써서, 개발자가 "내 파일" 앱으로 쌓이는지 본다.
     * shortcut: 다른 앱도 읽는 공용 폴더라 테스트 기기 전용, 본 앱(G1)에는 가져가지 않음
     */
    private fun mirrorToDownloads(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        val resolver = context.contentResolver
        val uri = findDownload(resolver) ?: resolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, DOWNLOAD_NAME)
                put(MediaStore.Downloads.RELATIVE_PATH, DOWNLOAD_DIR)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
            },
        ) ?: return
        resolver.openOutputStream(uri, "wt")?.use { out ->
            // BOM: 삼성 내 파일 텍스트 보기가 한글을 UTF-8로 읽게
            // 차이는 걸음을 읽은 사건(worker_fired, observer_fired)끼리만 비교한다
            var previousTotal: Long? = null
            val lines = read(context).joinToString("") { entry ->
                val total = if (entry["event"] in READ_EVENTS) ((entry["detail"] as? Map<*, *>)?.get("todayTotal") as? Number)?.toLong() else null
                val line = readable(entry, previousTotal)
                if (total != null) previousTotal = total
                line + "\n"
            }
            out.write(("\uFEFF" + lines).toByteArray())
        }
    }

    /** 한 줄 요약: 시각, 사건, 앱 상태, 오늘 합계(직전 합계와의 차이), 바뀐 기록 수와 걸음. */
    private fun readable(entry: Map<String, Any?>, previousTotal: Long?): String {
        val at = (entry["at"] as? Number)?.toLong() ?: 0L
        val time = Instant.ofEpochMilli(at).atZone(ZoneId.systemDefault()).toLocalTime().withNano(0)
        val detail = entry["detail"] as? Map<*, *> ?: emptyMap<Any, Any>()
        val today = (detail["todayTotal"] as? Number)?.toLong()?.takeIf { entry["event"] in READ_EVENTS }?.let { total ->
            // 날짜가 바뀌어 합계가 줄면 차이를 적지 않는다
            val diff = previousTotal?.let { total - it }?.takeIf { it >= 0 }?.let { " (+%,d)".format(it) } ?: ""
            "오늘 %,d보".format(total) + diff
        }
        val posted = (detail["diff"] as? Number)?.let { "알림 띄움 +%,d (%s)".format(it.toLong(), detail["source"] ?: "worker") }
        val samples = (detail["samples"] as? List<*>)?.mapNotNull { ((it as? Map<*, *>)?.get("count") as? Number)?.toLong() }
        val new = (detail["newSamples"] as? Number)?.let { n ->
            if (samples.isNullOrEmpty()) "바뀐 기록 $n" else "바뀐 기록 $n (${samples.joinToString(", ") { "%,d보".format(it) }})"
        }
        // T4: 예약 시각, 실제로 뜬 지연, 취소 시점
        val planned = (detail["plannedAt"] as? Number)?.toLong()?.takeIf { it > 0 }
            ?.let { "예약 " + Instant.ofEpochMilli(it).atZone(ZoneId.systemDefault()).toLocalTime().withNano(0) }
        val late = (detail["delaySec"] as? Number)?.let { "지연 ${it}초" }
        val cancelled = (detail["beforeSec"] as? Number)?.let { "예약 ${it}초 전 취소 (${detail["source"]})" }
        return listOfNotNull(time, "%-19s".format(entry["event"]), "%-10s".format(entry["appState"]), today, new, posted, planned, late, cancelled)
            .joinToString("  ")
    }

    private fun findDownload(resolver: ContentResolver): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME} = ? AND ${MediaStore.Downloads.RELATIVE_PATH} = ?",
            arrayOf(DOWNLOAD_NAME, DOWNLOAD_DIR),
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            return ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cursor.getLong(0))
        }
        return null
    }

    fun read(context: Context): List<Map<String, Any?>> {
        val file = file(context)
        if (!file.exists()) return emptyList()
        return file.readLines().mapNotNull { line -> runCatching { toMap(JSONObject(line)) }.getOrNull() }
    }

    fun clear(context: Context) {
        file(context).delete()
        runCatching { findDownload(context.contentResolver)?.let { context.contentResolver.delete(it, null, null) } }
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
