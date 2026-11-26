package co.itphy.rdc_health

import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals

internal class SegmentsTest {
    private val utc = ZoneId.of("UTC")
    private val min = 60_000L

    @Test
    fun walking_pairsEnterExit_andFiltersByRange() {
        val events = listOf(10 * min to true, 20 * min to false, 100 * min to true, 110 * min to false)
        val out = Segments.walking(events, 15 * min, 50 * min, 200 * min)
        assertEquals(listOf(Segment(10 * min, 20 * min, 0, "activityTransition")), out)
    }

    @Test
    fun walking_openEnter_endsAtNow() {
        val out = Segments.walking(listOf(10 * min to true), 0, 100 * min, 30 * min)
        assertEquals(30 * min, out.single().end)
    }

    @Test
    fun recording_dropsBelowThreshold() {
        val out = Segments.recording(listOf(Bucket(0, 5 * min, 49), Bucket(5 * min, 10 * min, 50)))
        assertEquals(listOf(Segment(5 * min, 10 * min, 50, "recording")), out)
    }

    @Test
    fun healthConnect_usesIncreaseBetweenPoints_andSkipsDayChange() {
        val day = 24 * 60 * min
        val totals = listOf(0L to 100L, 15 * min to 120L, 30 * min to 200L, day - min to 210L, day + min to 9500L)
        val out = Segments.healthConnect(totals, 0, 2 * day, utc)
        assertEquals(listOf(Segment(15 * min, 30 * min, 80, "healthConnect")), out)
    }

    @Test
    fun hours_includeZeroHours() {
        val hour = 60 * min
        val hours = Segments.hourStarts(0, 3 * hour, utc)
        val out = Segments.fillHours(hours, listOf(Bucket(hour, 2 * hour, 70)))
        assertEquals(listOf(0, 70, 0), out.map { it["steps"] })
    }

    @Test
    fun recording_clampFrom_limitsToTenDays() {
        val day = 24 * 60 * min
        assertEquals(90 * day, RecordingReader.clampFrom(0, 100 * day))
        assertEquals(95 * day, RecordingReader.clampFrom(95 * day, 100 * day))
    }
}
