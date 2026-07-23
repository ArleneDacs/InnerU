package com.valenin.inneru

import android.content.Intent
import android.view.WindowManager
import android.speech.tts.TextToSpeech
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity: FlutterActivity() {
    private val shareChannelName = "inneru/native_share"
    private val keepAwakeChannelName = "inneru/meditation_keep_awake"
    private val meditationFeedbackChannelName = "inneru/meditation_feedback"
    private var textToSpeech: TextToSpeech? = null
    private var textToSpeechReady = false
    private var pendingSpeech: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareImage" -> {
                        val filePath = call.argument<String>("filePath")
                        val text = call.argument<String>("text")

                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "Missing file path", null)
                            return@setMethodCallHandler
                        }

                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "Shared image not found", null)
                            return@setMethodCallHandler
                        }

                        val uri = FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            file
                        )
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "image/png"
                            putExtra(Intent.EXTRA_STREAM, uri)
                            if (!text.isNullOrBlank()) {
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            clipData = android.content.ClipData.newUri(contentResolver, "InnerU walk", uri)
                        }

                        startActivity(Intent.createChooser(intent, "Share recorded walk"))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, keepAwakeChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        textToSpeech = TextToSpeech(this) { status ->
            textToSpeechReady = status == TextToSpeech.SUCCESS
            if (textToSpeechReady) {
                textToSpeech?.language = Locale.getDefault()
                pendingSpeech?.let { text ->
                    speakText(text)
                    pendingSpeech = null
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, meditationFeedbackChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "speak" -> {
                        val text = call.argument<String>("text")?.trim().orEmpty()
                        if (text.isBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        if (!textToSpeechReady) {
                            pendingSpeech = text
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        speakText(text)
                        result.success(null)
                    }
                    "stop" -> {
                        textToSpeech?.stop()
                        pendingSpeech = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun speakText(text: String) {
        val engine = textToSpeech ?: return
        engine.stop()
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "inneru_meditation")
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }
}
