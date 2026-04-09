package dev.terra

/**
 * TerraConfig — Configuration for Terra initialization.
 *
 * Use [Builder] or the Kotlin DSL [terraConfig] to construct.
 * Maps 1:1 to terra_config_t fields in terra.h.
 */
class TerraConfig private constructor(
    val maxSpans: Int,
    val maxAttributesPerSpan: Int,
    val maxEventsPerSpan: Int,
    val maxEventAttrs: Int,
    val batchSize: Int,
    val flushIntervalMs: Long,
    val contentPolicy: ContentPolicy,
    val redactionStrategy: RedactionStrategy,
    val hmacKey: String?,
    val serviceName: String,
    val serviceVersion: String,
    val otlpEndpoint: String,
    val productionIngest: ProductionIngest?
) {

    data class ProductionIngest(
        val environmentName: String,
        val ingestKey: String,
        val installationId: String,
        val appBuild: String? = null,
        val additionalHeaders: Map<String, String> = emptyMap()
    )

    class Builder {
        var maxSpans: Int = 4096
        var maxAttributesPerSpan: Int = 128
        var maxEventsPerSpan: Int = 128
        var maxEventAttrs: Int = 16
        var batchSize: Int = 512
        var flushIntervalMs: Long = 5000L
        var contentPolicy: ContentPolicy = ContentPolicy.NEVER
        var redactionStrategy: RedactionStrategy = RedactionStrategy.HMAC_SHA256
        var hmacKey: String? = null
        var serviceName: String = "terra-android"
        var serviceVersion: String = "1.0.0"
        var otlpEndpoint: String = "http://localhost:4318"
        var productionIngest: ProductionIngest? = null

        fun maxSpans(value: Int) = apply { maxSpans = value }
        fun maxAttributesPerSpan(value: Int) = apply { maxAttributesPerSpan = value }
        fun maxEventsPerSpan(value: Int) = apply { maxEventsPerSpan = value }
        fun maxEventAttrs(value: Int) = apply { maxEventAttrs = value }
        fun batchSize(value: Int) = apply { batchSize = value }
        fun flushIntervalMs(value: Long) = apply { flushIntervalMs = value }
        fun contentPolicy(value: ContentPolicy) = apply { contentPolicy = value }
        fun redactionStrategy(value: RedactionStrategy) = apply { redactionStrategy = value }
        fun hmacKey(value: String?) = apply { hmacKey = value }
        fun serviceName(value: String) = apply { serviceName = value }
        fun serviceVersion(value: String) = apply { serviceVersion = value }
        fun otlpEndpoint(value: String) = apply { otlpEndpoint = value }
        fun productionIngest(value: ProductionIngest?) = apply { productionIngest = value }

        fun build(): TerraConfig = TerraConfig(
            maxSpans = maxSpans,
            maxAttributesPerSpan = maxAttributesPerSpan,
            maxEventsPerSpan = maxEventsPerSpan,
            maxEventAttrs = maxEventAttrs,
            batchSize = batchSize,
            flushIntervalMs = flushIntervalMs,
            contentPolicy = contentPolicy,
            redactionStrategy = redactionStrategy,
            hmacKey = hmacKey,
            serviceName = serviceName,
            serviceVersion = serviceVersion,
            otlpEndpoint = otlpEndpoint,
            productionIngest = productionIngest
        )
    }

    fun otlpHeaders(): Map<String, String> {
        val productionIngest = productionIngest ?: return emptyMap()
        return productionIngest.additionalHeaders + mapOf(
            "Authorization" to "Bearer ${productionIngest.ingestKey}"
        )
    }

    fun productionResourceAttributes(platform: String = "android"): Map<String, String> {
        val productionIngest = productionIngest ?: return emptyMap()
        val attributes = linkedMapOf(
            "terra.installation.id" to productionIngest.installationId,
            "service.instance.id" to productionIngest.installationId,
            "terra.platform" to platform.lowercase(),
            "terra.app.identifier" to serviceName,
            "terra.app.package_id" to serviceName,
            "terra.app.version" to serviceVersion,
            "deployment.environment.name" to productionIngest.environmentName,
            "deployment.environment" to productionIngest.environmentName
        )
        productionIngest.appBuild?.takeIf { it.isNotBlank() }?.let {
            attributes["terra.app.build"] = it
        }
        return attributes
    }

    fun httpTransport(
        connectTimeoutMs: Int = 10_000,
        readTimeoutMs: Int = 30_000
    ): TerraTransportAdapter =
        HttpTransport(
            endpoint = otlpEndpoint,
            connectTimeoutMs = connectTimeoutMs,
            readTimeoutMs = readTimeoutMs,
            headers = otlpHeaders()
        )

    fun okHttpTransport(client: Any): TerraTransportAdapter =
        OkHttpTransport(
            client = client,
            endpoint = otlpEndpoint,
            headers = otlpHeaders()
        )
}

/** Kotlin DSL for building [TerraConfig]. */
fun terraConfig(block: TerraConfig.Builder.() -> Unit): TerraConfig =
    TerraConfig.Builder().apply(block).build()

/** Content policy matching terra_content_policy_t. */
enum class ContentPolicy {
    /** Never capture prompt/response content. */
    NEVER,
    /** Capture only when explicitly opted in per-span. */
    OPT_IN,
    /** Always capture content. */
    ALWAYS;
}

/** Redaction strategy matching terra_redaction_strategy_t. */
enum class RedactionStrategy {
    /** Drop sensitive content entirely. */
    DROP,
    /** Replace with length indicator (e.g., "[42 chars]"). */
    LENGTH_ONLY,
    /** HMAC-SHA256 hash with configured key. */
    HMAC_SHA256;
}
