package com.example.saveduk

import android.content.Intent
import android.util.Log
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

class MainActivity : FlutterActivity() {
    companion object {
        private const val extractorLogTag = "SaveDukExtractor"

        // Keep this process-scoped: an Activity can be recreated while the app
        // stays open, and shutting down the old worker rejects later requests.
        private val extractorExecutor: ExecutorService = Executors.newSingleThreadExecutor()
        private val extractionSequence = AtomicLong(0)
    }

    private val shareChannelName = "saveduk/share"
    private val extractorChannelName = "saveduk/extractor"
    private var pendingSharePayload: Map<String, String>? = null
    private var shareChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSharePayload = extractSharedPayload(intent) ?: pendingSharePayload
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeSharedPayload" -> {
                        result.success(pendingSharePayload)
                        pendingSharePayload = null
                    }
                    "takeSharedText" -> {
                        result.success(pendingSharePayload?.get("url"))
                        pendingSharePayload = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, extractorChannelName).setMethodCallHandler { call, result ->
            if (call.method == "searchTracks") {
                val query = call.argument<String>("query") ?: ""
                val limit = call.argument<Int>("limit") ?: 10
                if (query.isBlank()) {
                    result.success(mapOf("tracks" to emptyList<Map<String, Any?>>()))
                    return@setMethodCallHandler
                }
                val requestId = extractionSequence.incrementAndGet()
                extractorExecutor.execute {
                    try {
                        if (!Python.isStarted()) {
                            Python.start(AndroidPlatform(applicationContext))
                        }
                        val raw = Python.getInstance()
                            .getModule("saveduk_native.bridge")
                            .callAttr("search_tracks", query, limit, requestId)
                            .toString()
                        val response = jsonToMap(JSONObject(raw))
                        runOnUiThread { result.success(response) }
                    } catch (e: Exception) {
                        Log.e(extractorLogTag, "searchTracks failure: ${e.message}")
                        runOnUiThread { result.error("search_failed", e.message, null) }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method == "setCookies") {
                val cookies = call.argument<String>("cookies") ?: ""
                try {
                    val cookieFile = java.io.File(applicationContext.filesDir, "saveduk_cookies.txt")
                    cookieFile.writeText(cookies)
                    Log.i(extractorLogTag, "cookies updated (${cookies.length} bytes)")
                    result.success(cookieFile.absolutePath)
                } catch (e: Exception) {
                    Log.e(extractorLogTag, "cookie write failed: ${e.message}")
                    result.error("cookie_error", "Failed to save cookies", null)
                }
                return@setMethodCallHandler
            }
            if (call.method == "getCookiePath") {
                val cookieFile = java.io.File(applicationContext.filesDir, "saveduk_cookies.txt")
                result.success(if (cookieFile.exists()) cookieFile.absolutePath else "")
                return@setMethodCallHandler
            }
            if (call.method == "clearCookies") {
                val cookieFile = java.io.File(applicationContext.filesDir, "saveduk_cookies.txt")
                if (cookieFile.exists()) cookieFile.delete()
                Log.i(extractorLogTag, "cookies cleared")
                result.success(null)
                return@setMethodCallHandler
            }
            if (call.method != "extract") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url.isNullOrBlank()) {
                result.error("invalid_url", "A media URL is required.", null)
                return@setMethodCallHandler
            }
            val cookieFile = java.io.File(applicationContext.filesDir, "saveduk_cookies.txt")
            val cookiePath = if (cookieFile.exists()) cookieFile.absolutePath else ""
            val requestId = extractionSequence.incrementAndGet()
            Log.i(extractorLogTag, "[$requestId] queued host=${urlHost(url)} cookies=${cookiePath.isNotEmpty()}")
            extractorExecutor.execute {
                try {
                    if (!Python.isStarted()) {
                        Log.i(extractorLogTag, "[$requestId] starting Python runtime")
                        Python.start(AndroidPlatform(applicationContext))
                    }
                    Log.d(extractorLogTag, "[$requestId] calling embedded extractor")
                    val raw = Python.getInstance()
                        .getModule("saveduk_native.bridge")
                        .callAttr("extract", url, requestId, cookiePath)
                        .toString()
                    val response = jsonToMap(JSONObject(raw))
                    val extractorError = response["error"] as? String
                    if (extractorError == null) {
                        Log.i(extractorLogTag, "[$requestId] stream selection succeeded")
                    } else {
                        Log.w(extractorLogTag, "[$requestId] extractor returned: $extractorError")
                    }
                    runOnUiThread { result.success(response) }
                } catch (error: Exception) {
                    Log.e(
                        extractorLogTag,
                        "[$requestId] native bridge failure " +
                            "type=${error.javaClass.simpleName} detail=${redact(error.message)}",
                    )
                    runOnUiThread {
                        result.error(
                            "extractor_failed",
                            "On-device extractor failed (E$requestId). Check Logcat tag $extractorLogTag.",
                            mapOf("requestId" to requestId, "exception" to error.javaClass.simpleName),
                        )
                    }
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "saveduk/foreground").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "Downloading…"
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_START
                        putExtra("title", title)
                    }
                    startForegroundService(intent)
                    result.success(null)
                }
                "update" -> {
                    val title = call.argument<String>("title") ?: "Downloading…"
                    val progress = call.argument<Int>("progress") ?: 0
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_UPDATE
                        putExtra("title", title)
                        putExtra("progress", progress)
                    }
                    startService(intent)
                    result.success(null)
                }
                "stop" -> {
                    val intent = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractSharedPayload(intent)?.let { payload ->
            pendingSharePayload = payload
            shareChannel?.invokeMethod("sharedPayload", payload)
            shareChannel?.invokeMethod("sharedText", payload["url"])
        }
    }

    private fun extractSharedPayload(intent: Intent?): Map<String, String>? {
        if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("text/") != true) {
            return null
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() } ?: return null
        val explicitMode = intent.getStringExtra("saveduk_mode")
        val className = intent.component?.className ?: ""
        val mode = if (explicitMode == "music" || className.contains("MusicShareActivity") || className.contains("ShareMusicActivity")) {
            "music"
        } else {
            "download"
        }
        return mapOf("url" to text, "mode" to mode)
    }

    private fun jsonToMap(value: JSONObject): Map<String, Any?> = buildMap {
        val keys = value.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            put(key, jsonValue(value.get(key)))
        }
    }

    private fun jsonValue(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> jsonToMap(value)
        is JSONArray -> List(value.length()) { index -> jsonValue(value.get(index)) }
        else -> value
    }

    private fun urlHost(value: String): String = try {
        android.net.Uri.parse(value).host ?: "invalid-host"
    } catch (_: Exception) {
        "invalid-host"
    }

    private fun redact(value: String?): String {
        if (value.isNullOrBlank()) return "none"
        return value.replace(Regex("https?://\\S+"), "[redacted-url]").take(300)
    }
}
