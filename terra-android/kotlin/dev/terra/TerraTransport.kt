package dev.terra

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * TerraTransport — OTLP/HTTP transport for Android.
 *
 * Sends OTLP protobuf payloads to a configured endpoint over HTTP.
 * Uses HttpURLConnection (zero extra dependencies) by default.
 * OkHttp adapter provided as [OkHttpTransport] for apps that already depend on it.
 *
 * The transport is used by the Zig core via the transport vtable. On Android,
 * the Kotlin-side transport is the recommended path since it benefits from
 * Android's connection pooling, certificate pinning, and network security config.
 */
interface TerraTransportAdapter {
    /**
     * Send OTLP protobuf data to the endpoint.
     * @param data Serialized OTLP protobuf bytes.
     * @return true on success (HTTP 2xx), false on failure.
     */
    fun send(data: ByteArray): Boolean

    /** Flush any buffered data. */
    fun flush()

    /** Release resources. */
    fun shutdown()
}

/**
 * Default transport using [HttpURLConnection].
 * Zero external dependencies.
 */
class HttpTransport(
    private val endpoint: String,
    private val connectTimeoutMs: Int = 10_000,
    private val readTimeoutMs: Int = 30_000,
    private val headers: Map<String, String> = emptyMap()
) : TerraTransportAdapter {

    override fun send(data: ByteArray): Boolean {
        val url = URL("$endpoint/v1/traces")
        val conn = url.openConnection() as HttpURLConnection
        return try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = connectTimeoutMs
            conn.readTimeout = readTimeoutMs
            conn.setRequestProperty("Content-Type", "application/x-protobuf")
            conn.setRequestProperty("Content-Length", data.size.toString())
            headers.forEach { (key, value) ->
                conn.setRequestProperty(key, value)
            }

            conn.outputStream.use { it.write(data) }

            val responseCode = conn.responseCode
            responseCode in 200..299
        } catch (_: IOException) {
            false
        } finally {
            conn.disconnect()
        }
    }

    override fun flush() {
        // HttpURLConnection sends immediately; no buffering.
    }

    override fun shutdown() {
        // No persistent resources to release.
    }
}

/**
 * OkHttp-based transport for apps that already depend on OkHttp.
 *
 * Usage:
 * ```kotlin
 * val client = OkHttpClient.Builder()
 *     .connectTimeout(10, TimeUnit.SECONDS)
 *     .build()
 * val transport = OkHttpTransport(client, "http://localhost:4318")
 * ```
 *
 * NOTE: This class references OkHttp types. It will fail to load at runtime
 * if OkHttp is not on the classpath. The Kotlin SDK does NOT declare an
 * OkHttp dependency — apps must provide it themselves.
 */
class OkHttpTransport(
    private val client: Any, // okhttp3.OkHttpClient — typed as Any to avoid compile-time dep
    private val endpoint: String,
    private val headers: Map<String, String> = emptyMap()
) : TerraTransportAdapter {

    override fun send(data: ByteArray): Boolean {
        return try {
            // Use reflection to avoid compile-time OkHttp dependency.
            // In a real Gradle build, you'd type this properly.
            val mediaType = Class.forName("okhttp3.MediaType")
                .getMethod("parse", String::class.java)
                .invoke(null, "application/x-protobuf")

            val requestBodyClass = Class.forName("okhttp3.RequestBody")
            val createMethod = requestBodyClass.getMethod(
                "create", Class.forName("okhttp3.MediaType"), ByteArray::class.java
            )
            val body = createMethod.invoke(null, mediaType, data)

            val requestBuilderClass = Class.forName("okhttp3.Request\$Builder")
            val builder = requestBuilderClass.getDeclaredConstructor().newInstance()
            requestBuilderClass.getMethod("url", String::class.java)
                .invoke(builder, "$endpoint/v1/traces")
            requestBuilderClass.getMethod("post", Class.forName("okhttp3.RequestBody"))
                .invoke(builder, body)
            headers.forEach { (key, value) ->
                requestBuilderClass.getMethod("addHeader", String::class.java, String::class.java)
                    .invoke(builder, key, value)
            }
            val request = requestBuilderClass.getMethod("build").invoke(builder)

            val callMethod = client.javaClass.getMethod("newCall", Class.forName("okhttp3.Request"))
            val call = callMethod.invoke(client, request)
            val response = call.javaClass.getMethod("execute").invoke(call)
            val code = response.javaClass.getMethod("code").invoke(response) as Int
            val responseBody = response.javaClass.getMethod("body").invoke(response)
            responseBody?.javaClass?.getMethod("close")?.invoke(responseBody)

            code in 200..299
        } catch (_: Exception) {
            false
        }
    }

    override fun flush() {
        // OkHttp dispatcher handles flushing.
    }

    override fun shutdown() {
        try {
            client.javaClass.getMethod("dispatcher").invoke(client)?.let { dispatcher ->
                dispatcher.javaClass.getMethod("executorService").invoke(dispatcher)?.let { executor ->
                    (executor as? java.util.concurrent.ExecutorService)?.shutdown()
                }
            }
        } catch (_: Exception) {
            // Best-effort shutdown.
        }
    }
}
