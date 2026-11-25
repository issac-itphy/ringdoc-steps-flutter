package co.itphy.rdc_health

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

// 결정: iOS와 같은 값. API에 임계값 인자가 없다. 움직임 구간 = 5분 칸에 50보 이상
internal const val SEGMENT_MINUTES = 5L
internal const val SEGMENT_MIN_STEPS = 50

internal data class Bucket(val start: Long, val end: Long, val steps: Int)

internal data class Segment(val start: Long, val end: Long, val steps: Int, val source: String) {
    fun toMap() = mapOf("start" to start, "end" to end, "steps" to steps, "source" to source)
}

/** 센서 읽기와 무관한 계산만 모았다(JVM 단위 테스트 대상). 시각은 모두 epoch ms. */
internal object Segments {
    /**
     * 걷기 전환(true=시작, false=끝)을 ENTER→EXIT 구간으로 묶어 [from,to]와 겹치는 것만 돌려준다.
     * 결정: 걸음 수는 알 수 없어 0으로 둔다. 호스트가 source로 구분한다
     * shortcut: 끝 신호를 놓쳐 열려 있는 구간은 now까지로 본다, 오탐이 보이면 상한을 둔다
     */
    fun walking(events: List<Pair<Long, Boolean>>, from: Long, to: Long, now: Long): List<Segment> {
        val out = mutableListOf<Segment>()
        var open: Long? = null
        for ((at, enter) in events.sortedBy { it.first }) {
            if (enter) {
                if (open == null) open = at
            } else if (open != null) {
                out += Segment(open, at, 0, "activityTransition")
                open = null
            }
        }
        if (open != null) out += Segment(open, now, 0, "activityTransition")
        return out.filter { it.start < to && it.end > from }
    }

    fun recording(buckets: List<Bucket>): List<Segment> =
        buckets.filter { it.steps >= SEGMENT_MIN_STEPS }.map { Segment(it.start, it.end, it.steps, "recording") }

    /** 연속한 두 (시각, 하루 합계) 점의 증가분이 임계값 이상이면 그 사이를 구간으로 본다. 날짜가 바뀌면 합계가 0으로 돌아가므로 건너뛴다. */
    fun healthConnect(totals: List<Pair<Long, Long>>, from: Long, to: Long, zone: ZoneId): List<Segment> =
        totals.sortedBy { it.first }.zipWithNext().mapNotNull { (a, b) ->
            val increase = b.second - a.second
            val sameDay = day(a.first, zone) == day(b.first, zone)
            if (sameDay && increase >= SEGMENT_MIN_STEPS && a.first < to && b.first > from) {
                Segment(a.first, b.first, increase.toInt(), "healthConnect")
            } else null
        }

    /** [from] 이전에서 가장 가까운 현지 시 정각부터 [to] 전까지의 1시간 칸 시작 시각. */
    fun hourStarts(from: Long, to: Long, zone: ZoneId): List<Long> {
        val out = mutableListOf<Long>()
        var h = Instant.ofEpochMilli(from).atZone(zone).truncatedTo(ChronoUnit.HOURS)
        while (h.toInstant().toEpochMilli() < to) {
            out += h.toInstant().toEpochMilli()
            h = h.plusHours(1)
        }
        return out
    }

    /** 걸음이 0인 시간도 포함한다(iOS와 같음). 칸 시작이 [h, 다음 정각)에 들면 그 시간에 더한다. */
    fun fillHours(hours: List<Long>, buckets: List<Bucket>): List<Map<String, Any>> =
        hours.mapIndexed { i, h ->
            val next = hours.getOrNull(i + 1) ?: Long.MAX_VALUE
            mapOf("hourStart" to h, "steps" to buckets.filter { it.start >= h && it.start < next }.sumOf { it.steps })
        }

    private fun day(ms: Long, zone: ZoneId) = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
}
