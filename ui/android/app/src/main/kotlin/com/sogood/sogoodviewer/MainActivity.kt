package com.sogood.sogoodviewer

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.sogoodviewer.app"
    private var methodChannel: MethodChannel? = null
    private var pendingFileToOpen: String? = null
    private var isFlutterReady: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    isFlutterReady = true
                    val file = pendingFileToOpen
                    pendingFileToOpen = null
                    result.success(file)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (Intent.ACTION_VIEW == action) {
            val uri: Uri? = intent.data
            if (uri != null) {
                if (uri.scheme == "file") {
                    val filePath = uri.path
                    if (filePath != null) {
                        dispatchOpenFile(filePath)
                    }
                } else if (uri.scheme == "content") {
                    Thread {
                        val filePath = resolveContentUri(uri)
                        if (filePath != null) {
                            runOnUiThread {
                                dispatchOpenFile(filePath)
                            }
                        }
                    }.start()
                }
            }
        }
    }

    private fun dispatchOpenFile(filePath: String) {
        if (isFlutterReady) {
            methodChannel?.invokeMethod("onOpenFile", filePath)
        } else {
            pendingFileToOpen = filePath
        }
    }

    private fun resolveContentUri(uri: Uri): String? {
        try {
            var displayName: String? = null
            val cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index != -1) {
                        displayName = it.getString(index)
                    }
                }
            }

            if (displayName.isNullOrEmpty()) {
                val type = contentResolver.getType(uri)
                val ext = if (type == "application/pdf") ".pdf" else ".md"
                displayName = "document$ext"
            }

            val sanitizedName = File(displayName!!).name
            val inboxDir = File(filesDir, "inbox").apply { mkdirs() }

            // Prune inbox directories, keeping up to 20 most recent sessions (LRU)
            val sessionDirs = inboxDir.listFiles { f -> f.isDirectory }
            if (sessionDirs != null && sessionDirs.size >= 20) {
                sessionDirs.sortBy { it.lastModified() }
                val toRemove = sessionDirs.size - 19
                for (i in 0 until toRemove) {
                    try { sessionDirs[i].deleteRecursively() } catch (_: Exception) {}
                }
            }

            // Create timestamped session subdirectory so original filename remains unpolluted
            val sessionDir = File(inboxDir, System.currentTimeMillis().toString()).apply { mkdirs() }
            val targetFile = File(sessionDir, sanitizedName)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }
            return targetFile.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("SuperGoodViewer", "Failed to resolve content URI: $uri", e)
            return null
        }
    }
}
