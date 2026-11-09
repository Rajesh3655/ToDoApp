package app.supare.offline

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import java.util.concurrent.Executors

/** Private, screenshot-protected image/PDF preview. Decrypted file lifetime is managed by Flutter caller. */
class PreviewActivity : Activity() {
    private var pdf: PdfRenderer? = null
    private var descriptor: ParcelFileDescriptor? = null
    private var bitmap: Bitmap? = null
    private var page = 0
    private val worker = Executors.newSingleThreadExecutor()
    private lateinit var image: ImageView
    private lateinit var status: TextView
    private lateinit var previous: Button
    private lateinit var next: Button
    private var destroyed = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        val path = intent.getStringExtra("path") ?: run { fail("Missing file"); return }
        val file = File(path).canonicalFile
        if (!file.isFile || !listOf(cacheDir,filesDir).any { file.path.startsWith(it.canonicalPath + File.separator) }) { fail("Invalid private preview path"); return }
        val padding = (16 * resources.displayMetrics.density).toInt()
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(padding,padding,padding,padding) }
        androidx.core.view.ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(androidx.core.view.WindowInsetsCompat.Type.systemBars())
            view.setPadding(padding + bars.left,padding + bars.top,padding + bars.right,padding + bars.bottom)
            insets
        }
        val close = Button(this).apply { text = "Close preview"; setOnClickListener { finish() } }
        root.addView(close)
        status = TextView(this).apply { gravity = Gravity.CENTER; setTextColor(Color.WHITE); text = "Opening securely…"; setPadding(0,12,0,12) }
        root.addView(status)
        image = ImageView(this).apply { scaleType = ImageView.ScaleType.FIT_CENTER; setBackgroundColor(Color.DKGRAY) }
        root.addView(image, LinearLayout.LayoutParams(-1,0,1f))
        val navigation = LinearLayout(this).apply { gravity = Gravity.CENTER }
        previous = Button(this).apply { text = "Previous page"; isEnabled = false; setOnClickListener { if (page > 0) { page--; renderPdf() } } }
        next = Button(this).apply { text = "Next page"; isEnabled = false; setOnClickListener { if (page + 1 < (pdf?.pageCount ?: 0)) { page++; renderPdf() } } }
        navigation.addView(previous); navigation.addView(next); root.addView(navigation)
        setContentView(root)
        try {
            if (intent.getStringExtra("mimeType") == "application/pdf") {
                descriptor = ParcelFileDescriptor.open(file,ParcelFileDescriptor.MODE_READ_ONLY)
                pdf = PdfRenderer(descriptor!!)
                require(pdf!!.pageCount > 0) { "This PDF has no pages" }
                renderPdf()
            } else {
                navigation.visibility = android.view.View.GONE
                worker.execute {
                    try {
                        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }; BitmapFactory.decodeFile(file.path,bounds)
                        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "This image format is not supported on this device" }
                        var sample = 1; while (bounds.outWidth / sample > 2048 || bounds.outHeight / sample > 2048) sample *= 2
                        val result = BitmapFactory.decodeFile(file.path,BitmapFactory.Options().apply { inSampleSize = sample }) ?: throw IllegalArgumentException("Cannot decode image")
                        runOnUiThread { if (destroyed) result.recycle() else { bitmap = result; image.setImageBitmap(result); status.text = "Private image preview" } }
                    } catch (error: Exception) { runOnUiThread { fail(error.message ?: "Cannot preview image") } }
                }
            }
        } catch (error: Exception) { fail(error.message ?: "Cannot preview file") }
    }
    private fun renderPdf() {
        previous.isEnabled = false; next.isEnabled = false; status.text = "Rendering page ${page + 1}…"
        val requested = page
        worker.execute {
            try {
                val result = pdf!!.openPage(requested).use { pdfPage ->
                    val width = minOf(1600,resources.displayMetrics.widthPixels.coerceAtLeast(600))
                    val height = (width.toDouble() * pdfPage.height / pdfPage.width).toInt().coerceIn(1,4000)
                    Bitmap.createBitmap(width,height,Bitmap.Config.ARGB_8888).also { it.eraseColor(Color.WHITE); pdfPage.render(it,null,null,PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY) }
                }
                runOnUiThread {
                    if (destroyed) result.recycle() else {
                        val old = bitmap; bitmap = result; image.setImageBitmap(result); old?.recycle()
                        status.text = "Page ${requested + 1} of ${pdf!!.pageCount}"; previous.isEnabled = requested > 0; next.isEnabled = requested + 1 < pdf!!.pageCount
                    }
                }
            } catch (error: Exception) { runOnUiThread { fail(error.message ?: "Cannot render PDF") } }
        }
    }
    private fun fail(message: String) { setResult(RESULT_CANCELED,Intent().putExtra("error",message)); finish() }
    override fun onDestroy() {
        destroyed = true
        worker.execute { try { pdf?.close(); descriptor?.close() } catch (_: Exception) {} }
        worker.shutdown(); if (::image.isInitialized) image.setImageDrawable(null); bitmap?.recycle(); bitmap = null
        super.onDestroy()
    }
}
