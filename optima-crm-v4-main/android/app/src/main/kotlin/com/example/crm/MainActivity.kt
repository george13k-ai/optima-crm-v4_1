package com.example.crm

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingXmlResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "crm/xml_picker",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickXmlText" -> pickXmlText(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun pickXmlText(result: MethodChannel.Result) {
        if (pendingXmlResult != null) {
            result.error("PICK_IN_PROGRESS", "Выбор файла уже выполняется.", null)
            return
        }
        pendingXmlResult = result

        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/xml", "application/xml"))
            }
            startActivityForResult(intent, 5001)
        } catch (e: Exception) {
            pendingXmlResult = null
            result.error("OPEN_FAILED", "Не удалось открыть выбор файла: ${e.message}", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 5001) return

        val result = pendingXmlResult ?: return
        pendingXmlResult = null

        if (resultCode != Activity.RESULT_OK) {
            result.error("CANCELED", "Выбор файла отменён.", null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.error("NO_URI", "Файл не выбран.", null)
            return
        }

        try {
            val text = contentResolver.openInputStream(uri)?.use { input ->
                String(input.readBytes(), Charsets.UTF_8)
            }
            if (text.isNullOrBlank()) {
                result.error("EMPTY_FILE", "Файл пустой или не читается.", null)
                return
            }
            result.success(text)
        } catch (e: Exception) {
            result.error("READ_FAILED", "Ошибка чтения XML: ${e.message}", null)
        }
    }
}
