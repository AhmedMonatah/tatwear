package com.example.tatweer

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Direct Bluetooth printer bridge for Honeywell/Intermec PR2 and PR3.
 * The invoice is rasterised locally, then sent over Bluetooth SPP as CPCL.
 * It deliberately does not depend on the obsolete LinePrintService application.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.tatweer/honeywell_printer"
    private val printerExecutor = Executors.newSingleThreadExecutor()
    private var bluetoothEnableResult: MethodChannel.Result? = null

    private companion object {
        const val enableBluetoothRequestCode = 9012
        const val maxCpclSliceHeight = 800
        const val writeChunkSize = 1024
        const val writePauseMillis = 10L
        val serialPortUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepareBluetooth" -> prepareBluetooth(result)
                    "listPrinters" -> result.success(listBondedPrinters())
                    "listAllBondedDevices" -> result.success(listAllBondedDevices())
                    "printPdf" -> runPrint(call, result, false)
                    "printTest" -> runPrint(call, result, true)
                    else -> result.notImplemented()
                }
            }
    }

    /** Android requires a user-confirmed system dialog to enable Bluetooth. */
    private fun prepareBluetooth(result: MethodChannel.Result) {
        try {
            requireBluetoothPermission()
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                result.error("BLUETOOTH_UNAVAILABLE", "هذا الهاتف لا يدعم Bluetooth.", null)
                return
            }
            if (adapter.isEnabled) {
                result.success(true)
                return
            }
            if (bluetoothEnableResult != null) {
                result.error("BLUETOOTH_REQUEST_IN_PROGRESS", "طلب تشغيل Bluetooth ظاهر بالفعل.", null)
                return
            }
            bluetoothEnableResult = result
            startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), enableBluetoothRequestCode)
        } catch (error: PrinterBridgeException) {
            result.error(error.code, error.message, error.cause?.toString())
        } catch (error: Exception) {
            result.error("BLUETOOTH_UNAVAILABLE", error.message, error.toString())
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != enableBluetoothRequestCode) return
        val result = bluetoothEnableResult ?: return
        bluetoothEnableResult = null
        if (BluetoothAdapter.getDefaultAdapter()?.isEnabled == true) {
            result.success(true)
        } else {
            result.error("BLUETOOTH_DISABLED", "لم يتم تشغيل Bluetooth. يلزم تشغيله لعرض الطابعات.", null)
        }
    }

    private fun runPrint(call: MethodCall, result: MethodChannel.Result, testOnly: Boolean) {
        val address = call.argument<String>("address")
        val printerId = call.argument<String>("printerId")
        if (address.isNullOrBlank() || printerId.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Printer address and profile are required.", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val pdfBytes = call.argument<ByteArray>("pdfBytes")
        if (!testOnly && (pdfBytes == null || pdfBytes.isEmpty())) {
            result.error("INVALID_ARGUMENT", "Invoice PDF is required.", null)
            return
        }

        printerExecutor.execute {
            try {
                requireBluetoothPermission()
                requireSupportedDirectProfile(printerId)
                val bytesWritten = if (testOnly) {
                    val testPage = createTestBitmap(printerId)
                    try {
                        printBitmaps(address, listOf(testPage))
                    } finally {
                        if (!testPage.isRecycled) testPage.recycle()
                    }
                } else {
                    val images = renderPdfPages(pdfBytes!!, printHeadWidth(printerId))
                    try {
                        printBitmaps(address, images)
                    } finally {
                        images.forEach { if (!it.isRecycled) it.recycle() }
                    }
                }
                runOnUiThread { result.success(mapOf("bytesWritten" to bytesWritten)) }
            } catch (error: PrinterBridgeException) {
                runOnUiThread { result.error(error.code, error.message, error.cause?.toString()) }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error(
                        "DIRECT_PRINT_FAILED",
                        "تعذّرت الطباعة المباشرة عبر Bluetooth: ${error.message ?: "خطأ غير معروف"}",
                        error.toString(),
                    )
                }
            }
        }
    }

    private fun listBondedPrinters(): List<Map<String, String>> = listBondedDevices(true)
    private fun listAllBondedDevices(): List<Map<String, String>> = listBondedDevices(false)

    private fun listBondedDevices(onlySupportedHoneywell: Boolean): List<Map<String, String>> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) return emptyList()
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return emptyList()
        return adapter.bondedDevices.orEmpty()
            .filter { !onlySupportedHoneywell || isSupportedHoneywellPrinter(it) }
            .map { device ->
                val name = device.name ?: device.address
                mapOf(
                    "name" to name,
                    "address" to device.address,
                    "printerId" to profileFor(name),
                    "isKnownHoneywell" to isSupportedHoneywellPrinter(device).toString(),
                )
            }
            .sortedBy { it["name"]?.lowercase() }
    }

    /** Opens the Bluetooth Serial Port Profile endpoint and writes CPCL jobs. */
    private fun printBitmaps(address: String, bitmaps: List<Bitmap>): Int {
        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: throw PrinterBridgeException("BLUETOOTH_UNAVAILABLE", "هذا الهاتف لا يدعم Bluetooth.")
        if (!adapter.isEnabled) throw PrinterBridgeException("BLUETOOTH_DISABLED", "فعّل Bluetooth ثم أعد المحاولة.")
        val device = try {
            adapter.getRemoteDevice(normaliseMacAddress(address))
        } catch (error: IllegalArgumentException) {
            throw PrinterBridgeException("INVALID_PRINTER_ADDRESS", "عنوان Bluetooth للطابعة غير صالح.", error)
        }
        adapter.cancelDiscovery()
        val socket = try {
            device.createRfcommSocketToServiceRecord(serialPortUuid)
        } catch (error: Exception) {
            throw PrinterBridgeException("BLUETOOTH_SOCKET_FAILED", "تعذّر إنشاء اتصال Bluetooth مع الطابعة.", error)
        }

        try {
            socket.connect()
            socket.outputStream.use { output ->
                var written = 0
                bitmaps.forEach { bitmap ->
                    cpclJobs(bitmap).forEach { job -> written += writeSafely(output, job) }
                }
                output.flush()
                return written
            }
        } catch (error: PrinterBridgeException) {
            throw error
        } catch (error: Exception) {
            throw PrinterBridgeException(
                "BLUETOOTH_PRINT_FAILED",
                "تعذّر الاتصال بالطابعة أو إرسال الفاتورة. تأكد أن الطابعة مقترنة وقريبة، وأن لغة PR3 مضبوطة على CSim/CPCL.",
                error,
            )
        } finally {
            try { socket.close() } catch (_: Exception) { }
        }
    }

    private fun writeSafely(output: OutputStream, data: ByteArray): Int {
        var offset = 0
        while (offset < data.size) {
            val count = minOf(writeChunkSize, data.size - offset)
            output.write(data, offset, count)
            offset += count
            if (offset < data.size) Thread.sleep(writePauseMillis)
        }
        return data.size
    }

    /** Splits a tall receipt, so printing continues naturally as items grow. */
    private fun cpclJobs(bitmap: Bitmap): List<ByteArray> {
        val jobs = mutableListOf<ByteArray>()
        var top = 0
        while (top < bitmap.height) {
            val height = minOf(maxCpclSliceHeight, bitmap.height - top)
            val bytesPerRow = (bitmap.width + 7) / 8
            val command = buildString {
                append("! 0 200 200 ").append(height).append(" 1\r\n")
                append("PW ").append(bitmap.width).append("\r\n")
                append("EG ").append(bytesPerRow).append(' ').append(height).append(" 0 0 ")
                append(bitmapToMonochromeHex(bitmap, top, height)).append("\r\nFORM\r\nPRINT\r\n")
            }
            jobs += command.toByteArray(Charsets.US_ASCII)
            top += height
        }
        return jobs
    }

    /** CPCL EG receives a 1-bit raster, most-significant bit first, as hex. */
    private fun bitmapToMonochromeHex(bitmap: Bitmap, top: Int, height: Int): String {
        val bytesPerRow = (bitmap.width + 7) / 8
        val hex = CharArray(bytesPerRow * height * 2)
        val row = IntArray(bitmap.width)
        var cursor = 0
        for (y in 0 until height) {
            bitmap.getPixels(row, 0, bitmap.width, 0, top + y, bitmap.width, 1)
            for (byteIndex in 0 until bytesPerRow) {
                var value = 0
                for (bit in 0 until 8) {
                    val x = byteIndex * 8 + bit
                    if (x < bitmap.width && isInkPixel(row[x])) value = value or (0x80 ushr bit)
                }
                hex[cursor++] = hexDigit(value ushr 4)
                hex[cursor++] = hexDigit(value)
            }
        }
        return String(hex)
    }

    private fun hexDigit(value: Int): Char = "0123456789ABCDEF"[value and 0x0F]

    private fun renderPdfPages(pdfBytes: ByteArray, targetWidth: Int): List<Bitmap> {
        val pdfFile = File.createTempFile("tatweer-invoice-", ".pdf", cacheDir)
        pdfFile.writeBytes(pdfBytes)
        val images = mutableListOf<Bitmap>()
        try {
            ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                PdfRenderer(descriptor).use { renderer ->
                    for (index in 0 until renderer.pageCount) {
                        renderer.openPage(index).use { page ->
                            val scale = targetWidth.toFloat() / page.width.toFloat()
                            val height = (page.height * scale).toInt().coerceAtLeast(1)
                            val bitmap = Bitmap.createBitmap(targetWidth, height, Bitmap.Config.ARGB_8888)
                            bitmap.eraseColor(Color.WHITE)
                            page.render(bitmap, null, Matrix().apply { setScale(scale, scale) }, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                            val receipt = cropBottomWhitespace(bitmap)
                            if (receipt !== bitmap) bitmap.recycle()
                            images += receipt
                        }
                    }
                }
            }
            return images
        } catch (error: Exception) {
            images.forEach { if (!it.isRecycled) it.recycle() }
            throw error
        } finally {
            pdfFile.delete()
        }
    }

    private fun createTestBitmap(printerId: String): Bitmap {
        val width = printHeadWidth(printerId)
        val bitmap = Bitmap.createBitmap(width, 440, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        paint.textSize = 35f
        canvas.drawText("Tatweer App", width / 2f, 80f, paint)
        paint.textSize = 24f
        paint.typeface = Typeface.DEFAULT
        canvas.drawText("Direct Bluetooth Raster Test", width / 2f, 135f, paint)
        canvas.drawText("Honeywell / Intermec $printerId", width / 2f, 180f, paint)
        canvas.drawLine(30f, 215f, width - 30f, 215f, paint)
        canvas.drawText("CPCL / CSim", width / 2f, 270f, paint)
        canvas.drawText("If you can read this, printing is ready.", width / 2f, 320f, paint)
        return bitmap
    }

    private fun cropBottomWhitespace(bitmap: Bitmap): Bitmap {
        val scanLine = IntArray(bitmap.width)
        var lastInkRow = -1
        for (row in bitmap.height - 1 downTo 0) {
            bitmap.getPixels(scanLine, 0, bitmap.width, 0, row, bitmap.width, 1)
            if (scanLine.any(::isInkPixel)) {
                lastInkRow = row
                break
            }
        }
        val receiptHeight = (lastInkRow + receiptBottomPaddingPixels).coerceIn(1, bitmap.height)
        return if (receiptHeight == bitmap.height) bitmap else Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, receiptHeight)
    }

    private fun isInkPixel(pixel: Int): Boolean {
        if (Color.alpha(pixel) < 16) return false
        return Color.red(pixel) < 200 || Color.green(pixel) < 200 || Color.blue(pixel) < 200
    }

    private fun requireBluetoothPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            throw PrinterBridgeException("BLUETOOTH_PERMISSION_DENIED", "التطبيق لا يملك صلاحية الاتصال بالبلوتوث. فعّلها من إعدادات التطبيق ثم حاول مرة أخرى.")
        }
    }

    private fun requireSupportedDirectProfile(printerId: String) {
        if (printerId !in setOf("PR2", "PR3")) {
            throw PrinterBridgeException("DIRECT_PROFILE_UNSUPPORTED", "الطباعة المباشرة الحالية مُختبرة لطابعات Honeywell PR2 وPR3 فقط. اختر موديل الطابعة الصحيح.")
        }
    }

    private fun normaliseMacAddress(address: String): String =
        address.replace(Regex("[^A-Fa-f0-9]"), "").chunked(2).joinToString(":")

    private fun profileFor(name: String): String = if (name.uppercase().contains("PR3")) "PR3" else "PR2"
    private fun isSupportedHoneywellPrinter(device: BluetoothDevice): Boolean {
        val value = device.name.orEmpty().uppercase()
        return value.contains("PR2") || value.contains("PR3")
    }
    private fun printHeadWidth(printerId: String): Int = if (printerId == "PR3") 576 else 384
    private val receiptBottomPaddingPixels: Int get() = 24

    private class PrinterBridgeException(
        val code: String,
        override val message: String,
        override val cause: Throwable? = null,
    ) : Exception(message, cause)
}
