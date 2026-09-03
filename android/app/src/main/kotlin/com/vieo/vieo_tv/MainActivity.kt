package com.vieo.vieo_tv

import android.app.Activity
import android.app.SearchManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter app and bridges two TV-specific pieces of the platform:
 * the system speech recognizer (the same voice prompt the launcher uses), and
 * search queries handed over by the assistant, e.g. "play CNN on Vieo TV".
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "vieo/voice"
        const val VOICE_REQUEST = 4001
    }

    private var channel: MethodChannel? = null
    private var pendingVoiceResult: MethodChannel.Result? = null

    /** Query the app was cold-started with; handed to Dart exactly once. */
    private var launchQuery: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        launchQuery = queryFrom(intent)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isRecognizerAvailable())
                    "listen" -> startVoiceSearch(result)
                    "consumeLaunchQuery" -> {
                        result.success(launchQuery)
                        launchQuery = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Already running: push the query straight through to Dart.
        queryFrom(intent)?.let { query ->
            channel?.invokeMethod("onSearchIntent", query)
        }
    }

    /** Pulls the search term out of the intents a TV assistant can send. */
    private fun queryFrom(intent: Intent?): String? {
        if (intent == null) return null
        val query = when (intent.action) {
            Intent.ACTION_SEARCH,
            "com.google.android.gms.actions.SEARCH_ACTION",
            "android.media.action.MEDIA_PLAY_FROM_SEARCH" ->
                intent.getStringExtra(SearchManager.QUERY)
            else -> null
        }
        return query?.takeIf { it.isNotBlank() }
    }

    private fun isRecognizerAvailable(): Boolean {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        return packageManager.queryIntentActivities(intent, 0).isNotEmpty()
    }

    private fun startVoiceSearch(result: MethodChannel.Result) {
        // One prompt at a time; a second request resolves as "nothing heard".
        if (pendingVoiceResult != null) {
            result.success(null)
            return
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Search channels")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

        try {
            pendingVoiceResult = result
            startActivityForResult(intent, VOICE_REQUEST)
        } catch (error: ActivityNotFoundException) {
            pendingVoiceResult = null
            result.success(null)
        }
    }

    @Deprecated("Flutter's activity still delivers results here.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VOICE_REQUEST) {
            val pending = pendingVoiceResult
            pendingVoiceResult = null
            val heard = if (resultCode == Activity.RESULT_OK) {
                data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            } else {
                null
            }
            pending?.success(heard)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
