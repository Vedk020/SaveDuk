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
    private var pendingSharedText: String? = null
    private var shareChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSharedText = extractSharedText(intent) ?: pendingSharedText
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "takeSharedText") {
                    result.success(pendingSharedText)
                    pendingSharedText = null
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, extractorChannelName).setMethodCallHandler { call, result ->
            if (call.method != "extract") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url")
            if (url.isNullOrBlank()) {
                result.error("invalid_url", "A media URL is required.", null)
                return@setMethodCallHandler
            }
            val requestId = extractionSequence.incrementAndGet()
            Log.i(extractorLogTag, "[$requestId] queued host=${urlHost(url)}")
            extractorExecutor.execute {
                try {
                    if (!Python.isStarted()) {
                        Log.i(extractorLogTag, "[$requestId] starting Python runtime")
                        Python.start(AndroidPlatform(applicationContext))
                    }
                    Log.d(extractorLogTag, "[$requestId] calling embedded extractor")
                    val raw = Python.getInstance()
                        .getModule("saveduk_native.bridge")
                        .callAttr("extract", url, requestId)
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
                    // Preserve the failure type and a redacted message in
                    // Logcat, but only expose a short request code to Flutter.
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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractSharedText(intent)?.let { text ->
            pendingSharedText = text
            shareChannel?.invokeMethod("sharedText", text)
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("text/") != true) {
            return null
        }
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }
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
