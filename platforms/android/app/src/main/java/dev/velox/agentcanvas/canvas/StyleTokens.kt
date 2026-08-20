package dev.velox.agentcanvas.canvas

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight

object StyleTokens {
    val plot = Color(0xFF599EFF)
    val previewLight = Color(0xFFF0F0F5)
    val previewDark = Color(0xFF212124)
    val overflow = Color(0xFFE65100)

    fun color(tone: CanvasTone?): Color? = when (tone) {
        CanvasTone.Critical -> Color(0xFFD32F2F)
        CanvasTone.Warning -> Color(0xFFEF6C00)
        CanvasTone.Success -> Color(0xFF2E7D32)
        CanvasTone.Info -> Color(0xFF1565C0)
        CanvasTone.Muted -> Color(0xFF6B6B70)
        null -> null
    }

    fun foreground(tone: CanvasTone?, default: Color): Color = color(tone) ?: default

    fun fontWeight(emphasis: CanvasEmphasis?): FontWeight = when (emphasis) {
        CanvasEmphasis.Strong -> FontWeight.SemiBold
        CanvasEmphasis.Subtle -> FontWeight.Light
        CanvasEmphasis.Normal, null -> FontWeight.Normal
    }

    fun trendColor(trend: String, tone: CanvasTone?): Color {
        color(tone)?.let { return it }
        val t = trend.trim()
        return when {
            t.startsWith("+") || t.contains("up", ignoreCase = true) -> Color(0xFF2E7D32)
            t.startsWith("-") || t.contains("down", ignoreCase = true) -> Color(0xFFEF6C00)
            else -> Color(0xFF6B6B70)
        }
    }
}

fun IconName.plainGlyph(): String = when (this) {
    IconName.Check -> "✓"
    IconName.Close -> "×"
    IconName.Warning, IconName.Alert -> "!"
    IconName.Info -> "i"
    IconName.Help -> "?"
    IconName.Sparkle -> "*"
    IconName.Search -> "Q"
    IconName.Link -> "@"
    IconName.Copy -> "="
    IconName.Refresh -> "↻"
    IconName.Play -> "▶"
    IconName.Pause -> "❚❚"
    IconName.Stop -> "■"
    IconName.Rocket -> "^"
    IconName.Bug -> "b"
    IconName.Clock -> "◷"
    IconName.Calendar -> "#"
    IconName.Person -> "p"
    IconName.People -> "pp"
    IconName.Folder -> "[]"
    IconName.File -> "_"
    IconName.Image -> "▣"
    IconName.Chart -> "≡"
    IconName.Settings -> "⚙"
    IconName.Lock -> "▣"
    IconName.Key -> "k"
    IconName.Cloud -> "~"
    IconName.Server -> "▣"
    IconName.Database -> "☰"
}
