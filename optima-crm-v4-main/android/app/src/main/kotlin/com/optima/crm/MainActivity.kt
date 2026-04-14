package com.optima.crm

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingFileResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "crm/import_picker",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickImportFile" -> pickImportFile(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun pickImportFile(result: MethodChannel.Result) {
        if (pendingFileResult != null) {
            result.error("PICK_IN_PROGRESS", "File picker is already in progress.", null)
            return
        }
        pendingFileResult = result

        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "text/xml",
                        "application/xml",
                        "application/vnd.ms-excel",
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                        "text/plain",
                    ),
                )
            }
            startActivityForResult(intent, 5001)
        } catch (e: Exception) {
            pendingFileResult = null
            result.error("OPEN_FAILED", "Failed to open file picker: ${e.message}", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 5001) return

        val result = pendingFileResult ?: return
        pendingFileResult = null

        if (resultCode != Activity.RESULT_OK) {
            result.error("CANCELED", "File selection was canceled.", null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.error("NO_URI", "No file selected.", null)
            return
        }

        try {
            val bytes = contentResolver.openInputStream(uri)?.use { input ->
                input.readBytes()
            }
            if (bytes == null || bytes.isEmpty()) {
                result.error("EMPTY_FILE", "File is empty or unreadable.", null)
                return
            }

            var fileName = "import_file"
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) {
                    fileName = cursor.getString(index) ?: fileName
                }
            }

            result.success(
                mapOf(
                    "fileName" to fileName,
                    "bytesBase64" to Base64.encodeToString(bytes, Base64.NO_WRAP),
                ),
            )
        } catch (e: Exception) {
            result.error("READ_FAILED", "File read error: ${e.message}", null)
        }
    }
}
