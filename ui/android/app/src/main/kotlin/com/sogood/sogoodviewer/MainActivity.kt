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

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (Intent.ACTION_VIEW == action) {
            val uri: Uri? = intent.data
            if (uri != null) {
                handleIncomingUri(uri)
            }
        } else if (Intent.ACTION_SEND == action) {
            val streamUri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            if (streamUri != null) {
                handleIncomingUri(streamUri)
                return
            }
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!sharedText.isNullOrBlank()) {
                Thread {
                    val savedPath = saveSharedMarkdownText(sharedText)
                    if (savedPath != null) {
                        runOnUiThread {
                            dispatchOpenFile(savedPath)
                        }
                    }
                }.start()
            }
        }
    }

    private fun handleIncomingUri(uri: Uri) {
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

            val mimeType = contentResolver.getType(uri)?.lowercase()
            if (displayName.isNullOrEmpty()) {
                val ext = if (mimeType == "application/pdf") ".pdf" else ".md"
                displayName = "document$ext"
            }

            val sanitizedName = File(displayName!!).name
            val sessionDir = prepareInboxSessionDir()
            var targetFile = File(sessionDir, sanitizedName)

            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }

            // Magic-byte sniff for extensionless or octet-stream files
            val lowerName = targetFile.name.lowercase()
            val hasKnownExt = lowerName.endsWith(".pdf") ||
                lowerName.endsWith(".md") ||
                lowerName.endsWith(".markdown") ||
                lowerName.endsWith(".mdown") ||
                lowerName.endsWith(".mkd") ||
                lowerName.endsWith(".mkdn")
            if (!hasKnownExt && targetFile.exists()) {
                val header = ByteArray(4)
                val readBytes = FileInputStream(targetFile).use { it.read(header) }
                val isPdfMagic = readBytes == 4 &&
                    header[0] == 0x25.toByte() && // '%'
                    header[1] == 0x50.toByte() && // 'P'
                    header[2] == 0x44.toByte() && // 'D'
                    header[3] == 0x46.toByte()    // 'F'
                val inferredExt = if (isPdfMagic || mimeType == "application/pdf") ".pdf" else ".md"
                val renamedFile = File(sessionDir, "${targetFile.name}$inferredExt")
                if (targetFile.renameTo(renamedFile)) {
                    targetFile = renamedFile
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
