package com.valenin.inneru

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val shareChannelName = "inneru/native_share"

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
    }
}
