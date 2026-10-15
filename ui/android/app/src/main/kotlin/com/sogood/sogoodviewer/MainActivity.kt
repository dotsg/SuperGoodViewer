package com.sogood.sogoodviewer

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.sogoodviewer.app"
    private var methodChannel: MethodChannel? = null
    private var pendingFileToOpen: String? = null
    private var isFlutterReady: Boolean = false
    private var isResolvingIntent: Boolean = false
    private var pendingInitialResult: MethodChannel.Result? = null

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
                    if (file != null) {
                        pendingFileToOpen = null
                        result.success(file)
                    } else if (isResolvingIntent) {
                        // Hold the result until the background URI copy finishes so cold-start
                        // from WeChat never misses the initial file due to copy latency.
                        pendingInitialResult = result
                    } else {
                        result.success(null)
                    }
                }
                "setKeepScreenOn" -> {
                    val enable = call.arguments as? Boolean ?: false
                    runOnUiThread {
                        if (enable) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(true)
                }
                "shareFile" -> {
                    val args = call.arguments as? Map<*, *>
                    val path = args?.get("path") as? String
                    val title = (args?.get("title") as? String) ?: "Share PDF"
                    if (path.isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        val shared = shareFileViaProvider(path, title)
                        result.success(shared)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun shareFileViaProvider(filePath: String, title: String): Boolean {
        return try {
            val srcFile = File(filePath)
            if (!srcFile.exists()) return false
            val shareDir = File(cacheDir, "shared_exports").apply { mkdirs() }
            val safeName = srcFile.name.ifEmpty { "document.pdf" }
            val targetFile = if (srcFile.parentFile?.canonicalPath == shareDir.canonicalPath) {
                srcFile
            } else {
                File(shareDir, safeName).also { dst ->
                    srcFile.copyTo(dst, overwrite = true)
                }
            }
            val authority = "$packageName.fileprovider"
            val contentUri = Uri.Builder()
                .scheme("content")
                .authority(authority)
                .appendPath(targetFile.name)
                .build()

            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = if (targetFile.name.lowercase().endsWith(".pdf")) "application/pdf" else "*/*"
                putExtra(Intent.EXTRA_STREAM, contentUri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(sendIntent, title).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            true
        } catch (e: Exception) {
            android.util.Log.e("SuperGoodViewer", "Failed to share file: $filePath", e)
            false
        }
    }

    private fun extractIntentStreamUri(intent: Intent): Uri? {
        intent.data?.let { return it }
        val streamUri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        if (streamUri != null) return streamUri
        val clip = intent.clipData
        if (clip != null && clip.itemCount > 0) {
            clip.getItemAt(0)?.uri?.let { return it }
        }
        return null
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (Intent.ACTION_VIEW == action) {
            val uri = extractIntentStreamUri(intent)
            if (uri != null) {
                handleIncomingUri(uri, intent.type)
            }
        } else if (Intent.ACTION_SEND == action) {
            val streamUri = extractIntentStreamUri(intent)
            if (streamUri != null) {
                handleIncomingUri(streamUri, intent.type)
                return
            }
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!sharedText.isNullOrBlank()) {
                isResolvingIntent = true
                Thread {
                    val savedPath = saveSharedMarkdownText(sharedText)
                    runOnUiThread {
                        completeResolvedFile(savedPath)
                    }
                }.start()
            }
        }
    }

    private fun handleIncomingUri(uri: Uri, intentType: String?) {
        if (uri.scheme == "file") {
            val filePath = uri.path
            if (filePath != null) {
                dispatchOpenFile(filePath)
            }
        } else if (uri.scheme == "content") {
            isResolvingIntent = true
            Thread {
                val filePath = resolveContentUri(uri, intentType)
                runOnUiThread {
                    completeResolvedFile(filePath)
                }
            }.start()
        }
    }

    private fun completeResolvedFile(filePath: String?) {
        isResolvingIntent = false
        val waiter = pendingInitialResult
        if (waiter != null) {
            pendingInitialResult = null
            waiter.success(filePath)
            return
        }
        if (filePath != null) {
            dispatchOpenFile(filePath)
        }
    }

    private fun saveSharedMarkdownText(text: String): String? {
        return try {
            val inboxDir = prepareInboxSessionDir()
            val targetFile = File(inboxDir, "shared_note.md")
            targetFile.writeText(text, Charsets.UTF_8)
            targetFile.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("SuperGoodViewer", "Failed to save shared text", e)
            null
        }
    }

    private fun prepareInboxSessionDir(): File {
        val inboxDir = File(filesDir, "inbox").apply { mkdirs() }
        val sessionDirs = inboxDir.listFiles { f -> f.isDirectory }
        if (sessionDirs != null && sessionDirs.size >= 20) {
            sessionDirs.sortBy { it.lastModified() }
            val toRemove = sessionDirs.size - 19
            for (i in 0 until toRemove) {
                try { sessionDirs[i].deleteRecursively() } catch (_: Exception) {}
            }
        }
        return File(inboxDir, System.currentTimeMillis().toString()).apply { mkdirs() }
    }

    private fun dispatchOpenFile(filePath: String) {
        val channel = methodChannel
        if (isFlutterReady && channel != null) {
            channel.invokeMethod("onOpenFile", filePath, object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    pendingFileToOpen = filePath
                }
                override fun notImplemented() {
                    pendingFileToOpen = filePath
                }
            })
        } else {
            pendingFileToOpen = filePath
        }
    }

    private fun hasPdfMagicBytes(file: File): Boolean {
        if (!file.exists() || file.length() < 4L) return false
        return try {
            val buf = ByteArray(1028)
            val readLen = FileInputStream(file).use { it.read(buf) }
            if (readLen < 4) return false
            val limit = readLen - 4
            for (i in 0..limit) {
                if (buf[i] == 0x25.toByte() &&     // '%'
                    buf[i + 1] == 0x50.toByte() && // 'P'
                    buf[i + 2] == 0x44.toByte() && // 'D'
                    buf[i + 3] == 0x46.toByte()    // 'F'
                ) {
                    return true
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun copyUriToFile(uri: Uri, targetFile: File): Boolean {
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
                if (targetFile.exists() && targetFile.length() > 0L) {
                    return true
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("SuperGoodViewer", "openInputStream failed for $uri, trying openFileDescriptor", e)
        }

        return try {
            contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                FileInputStream(pfd.fileDescriptor).use { input ->
                    FileOutputStream(targetFile).use { output ->
                        input.copyTo(output)
                    }
                }
            }
            targetFile.exists() && targetFile.length() > 0L
        } catch (e: Exception) {
            android.util.Log.e("SuperGoodViewer", "openFileDescriptor also failed for $uri", e)
            false
        }
    }

    private fun resolveContentUri(uri: Uri, intentType: String?): String? {
        try {
            var displayName: String? = null
            try {
                val cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                cursor?.use {
                    if (it.moveToFirst()) {
                        val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (index != -1) {
                            displayName = it.getString(index)
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.w("SuperGoodViewer", "DISPLAY_NAME query failed for $uri", e)
            }

            if (displayName.isNullOrBlank()) {
                val lastSeg = uri.lastPathSegment
                if (!lastSeg.isNullOrBlank()) {
                    val leaf = lastSeg.substringAfterLast('/')
                    if (leaf.isNotBlank()) {
                        displayName = leaf
                    }
                }
            }

            val providerMime = try {
                contentResolver.getType(uri)?.lowercase()
            } catch (_: Exception) {
                null
            }
            val effectiveMime = providerMime ?: intentType?.lowercase()

            val rawName = if (displayName.isNullOrBlank()) "document" else File(displayName!!).name
            val sanitizedName = rawName
                .replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), "_")
                .trim()
                .ifEmpty { "document" }

            val sessionDir = prepareInboxSessionDir()
            var targetFile = File(sessionDir, sanitizedName)

            if (!copyUriToFile(uri, targetFile)) {
                return null
            }

            // Always inspect magic bytes in the first 1024 bytes so PDFs from WeChat
            // (even with missing DISPLAY_NAME, octet-stream MIME, or cache filenames)
            // are guaranteed to have a .pdf extension.
            val isPdf = hasPdfMagicBytes(targetFile) || effectiveMime == "application/pdf"
            val lowerName = targetFile.name.lowercase()
            if (isPdf) {
                if (!lowerName.endsWith(".pdf")) {
                    val baseName = if (lowerName.endsWith(".md") || lowerName.endsWith(".bin") || lowerName.endsWith(".tmp")) {
                        targetFile.nameWithoutExtension.ifEmpty { "document" }
                    } else {
                        targetFile.name
                    }
                    val renamedFile = File(sessionDir, "$baseName.pdf")
                    if (targetFile.renameTo(renamedFile)) {
                        targetFile = renamedFile
                    }
                }
            } else {
                val hasMarkdownExt = lowerName.endsWith(".md") ||
                    lowerName.endsWith(".markdown") ||
                    lowerName.endsWith(".mdown") ||
                    lowerName.endsWith(".mkd") ||
                    lowerName.endsWith(".mkdn")
                if (!hasMarkdownExt) {
                    val renamedFile = File(sessionDir, "${targetFile.name}.md")
                    if (targetFile.renameTo(renamedFile)) {
                        targetFile = renamedFile
                    }
                }
            }

            return targetFile.absolutePath
        } catch (e: Exception) {
            android.util.Log.e("SuperGoodViewer", "Failed to resolve content URI: $uri", e)
            return null
        }
    }
}

/**
 * Lightweight, sandboxed ContentProvider for sharing exported PDFs from cacheDir/shared_exports
 * without requiring external AndroidX FileProvider XML resources.
 */
class ShareFileProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    private fun resolveFile(uri: Uri): File? {
        val ctx = context ?: return null
        val fileName = uri.lastPathSegment ?: return null
        val safeName = File(fileName).name
        val exportDir = File(ctx.cacheDir, "shared_exports")
        val file = File(exportDir, safeName)
        return if (file.exists() && file.isFile) file else null
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor? {
        val file = resolveFile(uri) ?: return null
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(cols, 1)
        val row = cursor.newRow()
        for (col in cols) {
            when (col) {
                OpenableColumns.DISPLAY_NAME -> row.add(file.name)
                OpenableColumns.SIZE -> row.add(file.length())
                else -> row.add(null)
            }
        }
        return cursor
    }

    override fun getType(uri: Uri): String {
        val name = uri.lastPathSegment?.lowercase() ?: ""
        return if (name.endsWith(".pdf")) "application/pdf" else "application/octet-stream"
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val file = resolveFile(uri) ?: return null
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}
