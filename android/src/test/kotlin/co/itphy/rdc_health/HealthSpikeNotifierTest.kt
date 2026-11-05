package co.itphy.rdc_health

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class HealthSpikeNotifierTest {
    @Test
    fun increase_firstCheck_onlySetsBaseline() = assertNull(HealthSpikeNotifier.increase(null, 3_390))

    @Test
    fun increase_moreSteps_returnsDiff() = assertEquals(64L, HealthSpikeNotifier.increase(3_390, 3_454))

    @Test
    fun increase_sameTotal_returnsNull() = assertNull(HealthSpikeNotifier.increase(3_454, 3_454))

    @Test
    fun increase_newDayResetsTotal_returnsNull() = assertNull(HealthSpikeNotifier.increase(3_454, 12))
}
