package dev.terra

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TerraHostContractTest {

    @Test
    fun `terra config DSL builds expected values`() {
        val config = terraConfig {
            serviceName = "host-test"
            serviceVersion = "2.0.0"
            otlpEndpoint = "http://localhost:4318"
            maxSpans = 128
            maxAttributesPerSpan = 16
            maxEventsPerSpan = 4
            maxEventAttrs = 2
            batchSize = 32
            flushIntervalMs = 250L
            contentPolicy = ContentPolicy.OPT_IN
            redactionStrategy = RedactionStrategy.HMAC_SHA256
            hmacKey = "host-secret"
        }

        assertEquals("host-test", config.serviceName)
        assertEquals("2.0.0", config.serviceVersion)
        assertEquals("http://localhost:4318", config.otlpEndpoint)
        assertEquals(128, config.maxSpans)
        assertEquals(16, config.maxAttributesPerSpan)
        assertEquals(4, config.maxEventsPerSpan)
        assertEquals(2, config.maxEventAttrs)
        assertEquals(32, config.batchSize)
        assertEquals(250L, config.flushIntervalMs)
        assertEquals(ContentPolicy.OPT_IN, config.contentPolicy)
        assertEquals(RedactionStrategy.HMAC_SHA256, config.redactionStrategy)
        assertEquals("host-secret", config.hmacKey)
    }

    @Test
    fun `span context formatting is stable`() {
        val context = SpanContext(
            traceIdHi = 0x0123456789ABCDEFL,
            traceIdLo = 0x0FEDCBA987654321L,
            spanId = 0x0011223344556677L
        )

        assertTrue(context.isValid)
        assertEquals("0123456789abcdef0fedcba987654321", context.traceIdHex())
        assertEquals("0011223344556677", context.spanIdHex())
    }

    @Test
    fun `terra resource returns host fallback off device`() {
        val attrs = TerraResource.collect()

        assertEquals("linux", attrs["os.type"])
        assertEquals("JVM", attrs["os.name"])
        assertEquals("non-android", attrs["terra.runtime"])
    }

    @Test
    fun `zero span context is invalid`() {
        assertFalse(SpanContext(0L, 0L, 0L).isValid)
    }
}
