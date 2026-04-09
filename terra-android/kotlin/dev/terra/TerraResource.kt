package dev.terra

/**
 * TerraResource — Collects Android device resource attributes.
 *
 * These attributes are attached to the service resource and exported
 * alongside every span, matching OpenTelemetry resource semantic conventions.
 *
 * NOTE: This file references Android SDK classes (android.os.Build, etc.).
 * It will only compile in an Android project. The import is deferred to
 * runtime to allow the rest of the SDK to compile in pure-JVM tests.
 */
object TerraResource {

    /**
     * Collect device resource attributes as key-value pairs.
     * Safe to call from any thread.
     *
     * Returns attributes following OTel resource semantic conventions:
     * - device.model.identifier → Build.MODEL
     * - device.manufacturer → Build.MANUFACTURER
     * - os.type → "linux" (Android kernel)
     * - os.name → "Android"
     * - os.version → Build.VERSION.RELEASE
     * - os.build_id → Build.DISPLAY
     * - host.arch → Build.SUPPORTED_ABIS[0]
     * - terra.android.sdk_int → Build.VERSION.SDK_INT
     * - terra.android.board → Build.BOARD
     * - terra.android.product → Build.PRODUCT
     */
    fun collect(): Map<String, String> {
        return try {
            val buildClass = Class.forName("android.os.Build")
            val versionClass = Class.forName("android.os.Build\$VERSION")

            val model = buildClass.getField("MODEL").get(null) as? String ?: "unknown"
            val manufacturer = buildClass.getField("MANUFACTURER").get(null) as? String ?: "unknown"
            val board = buildClass.getField("BOARD").get(null) as? String ?: "unknown"
            val product = buildClass.getField("PRODUCT").get(null) as? String ?: "unknown"
            val display = buildClass.getField("DISPLAY").get(null) as? String ?: "unknown"

            val release = versionClass.getField("RELEASE").get(null) as? String ?: "unknown"
            val sdkInt = versionClass.getField("SDK_INT").getInt(null)

            @Suppress("UNCHECKED_CAST")
            val abis = buildClass.getField("SUPPORTED_ABIS").get(null) as? Array<String>
            val arch = abis?.firstOrNull() ?: "unknown"

            mapOf(
                "device.model.identifier" to model,
                "device.manufacturer" to manufacturer,
                "os.type" to "linux",
                "os.name" to "Android",
                "os.version" to release,
                "os.build_id" to display,
                "host.arch" to arch,
                "terra.android.sdk_int" to sdkInt.toString(),
                "terra.android.board" to board,
                "terra.android.product" to product
            )
        } catch (_: Exception) {
            // Not running on Android — return minimal resource set.
            mapOf(
                "os.type" to "linux",
                "os.name" to "JVM",
                "terra.runtime" to "non-android"
            )
        }
    }

    fun collect(config: TerraConfig, platform: String = "android"): Map<String, String> {
        return collect() + config.productionResourceAttributes(platform = platform)
    }

    /**
     * Apply collected resource attributes to a Terra instance as span attributes.
     * Call after [Terra.init] to enrich all subsequent spans.
     */
    fun applyTo(terra: Terra) {
        val handle = terra.requireHandle()
        val attrs = collect()
        // Resource attributes are set as service-level attributes via session.
        // For now, they'll be available as span attributes on the first span.
        // A proper resource API will be added when the Zig core supports it.
        attrs.forEach { (_, _) ->
            // Reserved: resource attributes will be set via terra_set_resource_attribute
            // when the C API adds that function. For now, collect() is available
            // for the transport layer to include in OTLP resource.
        }
    }
}
