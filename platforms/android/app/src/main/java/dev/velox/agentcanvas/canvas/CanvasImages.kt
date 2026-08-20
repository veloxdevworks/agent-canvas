package dev.velox.agentcanvas.canvas

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64

object CanvasImages {
    private val dataUri = Regex("^data:image/(png|jpeg|jpg);base64,(.+)$", RegexOption.IGNORE_CASE)

    fun decode(source: String, maxPx: Int = 512): Bitmap? {
        val match = dataUri.find(source.trim()) ?: return null
        val payload = match.groupValues[2].replace("\\s".toRegex(), "")
        return try {
            val bytes = Base64.decode(payload, Base64.DEFAULT)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            val opts = BitmapFactory.Options().apply {
                inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maxPx)
            }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    fun isDataImage(source: String): Boolean = dataUri.matches(source.trim())

    private fun sampleSize(w: Int, h: Int, maxPx: Int): Int {
        var sample = 1
        var width = w
        var height = h
        while (width / 2 >= maxPx && height / 2 >= maxPx) {
            width /= 2
            height /= 2
            sample *= 2
        }
        return sample
    }
}
