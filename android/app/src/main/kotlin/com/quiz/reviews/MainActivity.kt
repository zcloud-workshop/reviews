package com.quiz.reviews

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.apache.poi.hwpf.HWPFDocument
import org.apache.poi.hwpf.extractor.WordExtractor
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    companion object {
        private const val SHARED_CHANNEL = "com.quiz.reviews/shared_file"
        private const val DOCUMENT_CHANNEL = "com.quiz.reviews/document_reader"
        private const val MAX_FILE_BYTES = 20L * 1024 * 1024
    }

    private var sharedChannel: MethodChannel? = null
    private var pendingFile: Map<String, Any>? = null
    private var dartReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharedChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARED_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "getInitialSharedFile") {
                    dartReady = true
                    val file = pendingFile ?: readIntent(intent)
                    pendingFile = null
                    result.success(file)
                } else {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOCUMENT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "extractDoc") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("invalid_file", "DOC 文件路径无效。", null)
                return@setMethodCallHandler
            }
            thread(name = "doc-text-reader") {
                try {
                    val text = extractDoc(path)
                    runOnUiThread { result.success(text) }
                } catch (error: Throwable) {
                    runOnUiThread {
                        result.error(
                            "doc_read_error",
                            "DOC 文件读取失败，请先用 Word/WPS 另存为 DOCX。",
                            error.message,
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingFile = readIntent(intent)
        if (dartReady) {
            pendingFile?.let { sharedChannel?.invokeMethod("sharedFile", it) }
            pendingFile = null
        }
    }

    private fun extractDoc(path: String): String {
        val file = File(path)
        require(file.isFile && file.canRead()) { "无法访问所选文件" }
        require(file.length() <= MAX_FILE_BYTES) { "文件不能超过 20 MB" }
        return FileInputStream(file).use { input ->
            HWPFDocument(input).use { document ->
                WordExtractor(document).use { it.text }
            }
        }
    }

    private fun readIntent(source: Intent): Map<String, Any>? {
        val uri = intentUris(source).firstOrNull() ?: return null
        return readUri(uri)
    }

    private fun intentUris(source: Intent): List<Uri> {
        val result = mutableListOf<Uri>()
        when (source.action) {
            Intent.ACTION_VIEW -> source.data?.let(result::add)
            Intent.ACTION_SEND -> {
                source.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(result::add)
                addClipUris(source, result)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                source.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?.let(result::addAll)
                addClipUris(source, result)
            }
        }
        if (result.isEmpty()) {
            val text = source.getStringExtra(Intent.EXTRA_TEXT)?.trim()
            if (text?.startsWith("content://") == true ||
                text?.startsWith("file://") == true
            ) result.add(Uri.parse(text))
        }
        return result.distinct()
    }

    private fun addClipUris(source: Intent, result: MutableList<Uri>) {
        source.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) {
                clip.getItemAt(index).uri?.let(result::add)
            }
        }
    }

    private fun readUri(uri: Uri): Map<String, Any> {
        val tempFile = File(cacheDir, "shared_${System.currentTimeMillis()}.tmp")
        return try {
            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "无法打开文件" }
                FileOutputStream(tempFile).use { output ->
                    val buffer = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= MAX_FILE_BYTES) { "文件不能超过 20 MB" }
                        output.write(buffer, 0, count)
                    }
                }
            }

            val rawName = displayName(uri)
            val mimeType = contentResolver.getType(uri).orEmpty()
            val extension = detectExtension(rawName, mimeType, tempFile)
            val namedExtension = rawName.substringAfterLast('.', "").lowercase()
            val name = if (namedExtension in setOf("json", "doc", "docx", "txt")) {
                rawName
            } else {
                "$rawName.$extension"
            }
            val cached = File(cacheDir, "shared_${System.currentTimeMillis()}.$extension")
            if (!tempFile.renameTo(cached)) {
                tempFile.copyTo(cached, overwrite = true)
                tempFile.delete()
            }
            mapOf(
                "name" to name,
                "mimeType" to mimeType,
                "path" to cached.absolutePath,
            )
        } catch (error: Throwable) {
            tempFile.delete()
            mapOf("error" to "无法读取分享文件：${error.message ?: "请重新下载后再试"}")
        }
    }

    private fun detectExtension(name: String, mimeType: String, file: File): String {
        val named = name.substringAfterLast('.', "").lowercase()
        if (named in setOf("json", "doc", "docx", "txt")) return named
        return when {
            mimeType == "application/json" || mimeType == "text/json" -> "json"
            mimeType == "application/msword" -> "doc"
            mimeType.contains("wordprocessingml.document") -> "docx"
            mimeType == "text/plain" -> "txt"
            else -> detectContent(file)
        }
    }

    private fun detectContent(file: File): String {
        val header = ByteArray(512)
        val count = FileInputStream(file).use { it.read(header) }.coerceAtLeast(0)
        if (count >= 4 && header[0] == 0x50.toByte() && header[1] == 0x4B.toByte()) {
            return "docx"
        }
        if (count >= 8 && header.take(8).map { it.toInt() and 0xFF } ==
            listOf(0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1)
        ) return "doc"
        val text = header.copyOf(count).toString(Charsets.UTF_8).trimStart()
        if (text.startsWith("{") || text.startsWith("[")) return "json"
        throw IllegalArgumentException("仅支持 JSON、DOCX 和 DOC 文件")
    }

    private fun displayName(uri: Uri): String {
        if (uri.scheme == "content") {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) return cursor.getString(index)
                }
            }
        }
        return uri.lastPathSegment ?: "shared_question_bank"
    }
}
