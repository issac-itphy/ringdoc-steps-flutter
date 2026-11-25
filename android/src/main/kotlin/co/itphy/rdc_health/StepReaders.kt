package co.itphy.rdc_health

import android.content.Context
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.google.android.gms.fitness.FitnessLocal
import com.google.android.gms.fitness.data.LocalDataType
import com.google.android.gms.fitness.request.LocalDataReadRequest
import com.google.android.gms.tasks.Tasks
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.TimeUnit

/** Recording API(Play 서비스가 폰 센서로 쌓는 걸음). 블로킹이라 IO 스레드에서 부른다. */
internal object RecordingReader {
    fun buckets(c: Context, from: Long, to: Long, size: Long, unit: TimeUnit): List<Bucket> {
        val request = LocalDataReadRequest.Builder()
            .aggregate(LocalDataType.TYPE_STEP_COUNT_DELTA)
            .bucketByTime(size.toInt(), unit)
            .setTimeRange(from, to, TimeUnit.MILLISECONDS)
            .build()
        val response = Tasks.await(FitnessLocal.getLocalRecordingClient(c).readData(request), 20, TimeUnit.SECONDS)
        return response.buckets.map { b ->
            val steps = b.dataSets.flatMap { it.dataPoints }.sumOf { p -> p.dataType.fields.sumOf { p.getValue(it).asInt() } }
            Bucket(b.getStartTime(TimeUnit.MILLISECONDS), b.getEndTime(TimeUnit.MILLISECONDS), steps)
        }
    }
}

/** Health Connect는 보조 신호다. 없거나 권한이 없어도 호출하는 쪽이 그 소스만 건너뛴다. */
internal object HealthConnectSteps {
    // 결정: API 28 미만은 Health Connect 호출 자체를 건너뛴다
    fun isAvailable(c: Context) =
        Build.VERSION.SDK_INT >= 28 && HealthConnectClient.getSdkStatus(c) == HealthConnectClient.SDK_AVAILABLE

    /** 오늘 00:00부터 지금까지의 합계를 (시각, 합계)로 남긴다. */
    suspend fun recordTotal(c: Context) {
        val zone = ZoneId.systemDefault()
        val now = Instant.now()
        val start = now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
        val total = HealthConnectClient.getOrCreate(c)
            .aggregate(AggregateRequest(setOf(StepsRecord.COUNT_TOTAL), TimeRangeFilter.between(start, now)))[StepsRecord.COUNT_TOTAL]
        Store.addTotal(c, now.toEpochMilli(), total ?: 0L)
    }
}
