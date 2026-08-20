package dev.velox.agentcanvas.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF1B1B1F),
    onPrimary = Color(0xFFFFFFFF),
    secondary = Color(0xFF4A4A4F),
    onSecondary = Color(0xFFFFFFFF),
    background = Color(0xFFF6F6F8),
    onBackground = Color(0xFF1B1B1F),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF1B1B1F),
    surfaceVariant = Color(0xFFE8E8EC),
    onSurfaceVariant = Color(0xFF5C5C62),
    error = Color(0xFFB3261E),
    outline = Color(0xFFC6C6CC),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFE4E4E8),
    onPrimary = Color(0xFF1B1B1F),
    secondary = Color(0xFFB8B8BE),
    onSecondary = Color(0xFF1B1B1F),
    background = Color(0xFF121214),
    onBackground = Color(0xFFE4E4E8),
    surface = Color(0xFF1C1C1F),
    onSurface = Color(0xFFE4E4E8),
    surfaceVariant = Color(0xFF2A2A2E),
    onSurfaceVariant = Color(0xFFB8B8BE),
    error = Color(0xFFF2B8B5),
    outline = Color(0xFF45454A),
)

@Composable
fun AgentCanvasTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    MaterialTheme(
        colorScheme = if (dark) DarkColors else LightColors,
        content = content,
    )
}
