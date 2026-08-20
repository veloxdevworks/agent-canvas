package dev.velox.agentcanvas.widget

import android.content.Intent
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import dev.velox.agentcanvas.MainActivity
import dev.velox.agentcanvas.canvas.CanvasDefinition
import dev.velox.agentcanvas.canvas.CanvasDocument
import dev.velox.agentcanvas.canvas.CanvasImages
import dev.velox.agentcanvas.canvas.CanvasSection
import dev.velox.agentcanvas.canvas.CanvasSize
import dev.velox.agentcanvas.canvas.CanvasTone
import dev.velox.agentcanvas.canvas.ChartType
import dev.velox.agentcanvas.canvas.ContentClip
import dev.velox.agentcanvas.canvas.IconName
import dev.velox.agentcanvas.canvas.ListItem
import dev.velox.agentcanvas.canvas.MetricItem
import dev.velox.agentcanvas.canvas.StyleTokens
import dev.velox.agentcanvas.canvas.plainGlyph

@Composable
fun GlanceCanvasTile(
    document: CanvasDocument,
    definition: CanvasDefinition,
) {
    val glanceSize: DpSize = LocalSize.current
    val size = CanvasSize.fromGlance(glanceSize.width.value, glanceSize.height.value)
    val hasTitle = ContentClip.showsDocumentTitle(document, size)
    val hasTimestamp = !document.updatedAt.isNullOrBlank()
    var budget = ContentClip.contentBudget(
        displayHeight = glanceSize.height.value,
        size = size,
        hasTitle = hasTitle && !document.isEmptyContent,
        hasTimestamp = hasTimestamp && !document.isEmptyContent,
        reserveOverflowLine = false,
    )
    var clip = ContentClip.apply(document, size, budget)
    if (clip.truncated) {
        budget = ContentClip.contentBudget(
            displayHeight = glanceSize.height.value,
            size = size,
            hasTitle = hasTitle && !document.isEmptyContent,
            hasTimestamp = hasTimestamp && !document.isEmptyContent,
            reserveOverflowLine = true,
        )
        clip = ContentClip.apply(document, size, budget)
    }

    val context = LocalContext.current
    val openHost = actionStartActivity(Intent(context, MainActivity::class.java))
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(16.dp)
            .clickable(openHost),
    ) {
        when {
            document.isEmptyContent -> GlanceEmpty(definition, size)
            document.cover != null -> GlanceCover(document, size, clip)
            else -> GlancePacked(document, size, clip)
        }
    }
}

@Composable
private fun GlanceEmpty(definition: CanvasDefinition, size: CanvasSize) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(ContentClip.edgeInset(size).dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "No content",
            style = TextStyle(
                color = GlanceTheme.colors.onSurface,
                fontSize = if (size == CanvasSize.Small) 13.sp else 15.sp,
                fontWeight = FontWeight.Bold,
            ),
            maxLines = 1,
        )
        Text(
            text = definition.displayName,
            style = TextStyle(
                color = GlanceTheme.colors.onSurfaceVariant,
                fontSize = 11.sp,
            ),
            maxLines = 2,
        )
    }
}

@Composable
private fun GlanceCover(document: CanvasDocument, size: CanvasSize, clip: ContentClip.Result) {
    val cover = document.cover ?: return
    val bitmap = CanvasImages.decode(cover.source)
    if (bitmap != null) {
        Image(
            provider = ImageProvider(bitmap),
            contentDescription = cover.alt,
            modifier = GlanceModifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
        )
    } else {
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(ContentClip.edgeInset(size).dp),
            verticalAlignment = Alignment.Top,
            horizontalAlignment = Alignment.Start,
        ) {
            Text(
                text = cover.alt.ifBlank { "Cover unavailable" },
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp),
                maxLines = 1,
            )
            GlancePacked(document.withoutCover, size, clip)
        }
    }
}

@Composable
private fun GlancePacked(document: CanvasDocument, size: CanvasSize, clip: ContentClip.Result) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(ContentClip.edgeInset(size).dp),
        verticalAlignment = Alignment.Top,
        horizontalAlignment = Alignment.Start,
    ) {
        if (ContentClip.showsDocumentTitle(document, size)) {
            Text(
                text = document.title.orEmpty(),
                style = TextStyle(
                    color = GlanceTheme.colors.onSurface,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
            Spacer(GlanceModifier.height(4.dp))
        }
        clip.shown.forEach { section ->
            GlanceSection(section, size, clip)
            Spacer(GlanceModifier.height(4.dp))
        }
        Spacer(GlanceModifier.defaultWeight())
        if (clip.truncated) {
            Text(
                text = ContentClip.overflowCaption(clip, size),
                style = TextStyle(
                    color = ColorProvider(StyleTokens.overflow),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 1,
            )
        }
        document.updatedAt?.takeIf { it.isNotBlank() }?.let { stamp ->
            Text(
                text = "Updated $stamp",
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 9.sp),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun GlanceSection(section: CanvasSection, size: CanvasSize, clip: ContentClip.Result) {
    when (section) {
        is CanvasSection.Header -> {
            Text(
                text = buildString {
                    section.icon?.let { append(it.plainGlyph()).append(' ') }
                    append(section.text)
                },
                style = TextStyle(
                    color = toneProvider(section.tone, GlanceTheme.colors.onSurface),
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                ),
                maxLines = 2,
            )
            section.subtitle?.takeIf { it.isNotBlank() }?.let {
                Text(
                    text = it,
                    style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp),
                    maxLines = 1,
                )
            }
        }
        is CanvasSection.Text -> Text(
            text = section.content,
            style = TextStyle(
                color = toneProvider(section.tone, GlanceTheme.colors.onSurface),
                fontSize = 11.sp,
            ),
            maxLines = if (size == CanvasSize.Small) 2 else 3,
        )
        is CanvasSection.Metrics -> GlanceMetrics(section.items, size)
        is CanvasSection.Chart -> GlanceChartPlaceholder(section, size)
        is CanvasSection.ListSection -> GlanceList(section.title, section.items, size)
        is CanvasSection.Image -> GlanceImage(section, size)
        is CanvasSection.Spacer -> Spacer(GlanceModifier.height((section.size?.gapPoints ?: 4f).dp))
        is CanvasSection.Group -> {
            // Detail-only in schema; flatten children if present.
            section.children.forEach { GlanceSection(it, size, clip) }
        }
        is CanvasSection.Progress -> {
            val max = section.max?.takeIf { it > 0 } ?: 1.0
            val frac = (section.value / max).toFloat().coerceIn(0f, 1f)
            section.label?.takeIf { it.isNotBlank() }?.let {
                Text(it, style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 10.sp), maxLines = 1)
            }
            LinearProgressIndicator(
                progress = frac,
                modifier = GlanceModifier.fillMaxWidth().height(6.dp),
                color = toneProvider(section.tone, GlanceTheme.colors.primary),
                backgroundColor = GlanceTheme.colors.surfaceVariant,
            )
        }
        is CanvasSection.Divider -> Box(
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(1.dp)
                .background(GlanceTheme.colors.outline),
        ) {}
        is CanvasSection.KeyValue -> {
            section.items.forEach { item ->
                Row(modifier = GlanceModifier.fillMaxWidth()) {
                    Text(
                        text = item.key,
                        style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp),
                        maxLines = 1,
                        modifier = GlanceModifier.defaultWeight(),
                    )
                    Text(
                        text = item.value,
                        style = TextStyle(
                            color = toneProvider(item.tone, GlanceTheme.colors.onSurface),
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        maxLines = 1,
                    )
                }
            }
        }
        is CanvasSection.Badges -> {
            Text(
                text = section.items.joinToString("  ") { it.text },
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp),
                maxLines = 1,
            )
        }
        is CanvasSection.Icon -> Text(
            text = section.name.plainGlyph(),
            style = TextStyle(
                color = toneProvider(section.tone, GlanceTheme.colors.onSurfaceVariant),
                fontSize = 16.sp,
            ),
            maxLines = 1,
        )
    }
}

@Composable
private fun GlanceMetrics(items: List<MetricItem>, size: CanvasSize) {
    val visible = items.take(if (size == CanvasSize.Small) 2 else 4)
    Row(modifier = GlanceModifier.fillMaxWidth()) {
        visible.forEach { item ->
            Column(modifier = GlanceModifier.defaultWeight()) {
                Text(
                    text = item.value,
                    style = TextStyle(
                        color = toneProvider(item.tone, GlanceTheme.colors.onSurface),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                    ),
                    maxLines = 1,
                )
                Text(
                    text = buildString {
                        append(item.label)
                        item.trend?.takeIf { it.isNotBlank() }?.let { append(' ').append(it) }
                    },
                    style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun GlanceChartPlaceholder(section: CanvasSection.Chart, size: CanvasSize) {
    val plotH = ContentClip.chartPlotHeight(size, 0.7f)
    Column {
        section.title?.takeIf { it.isNotBlank() }?.let {
            Text(
                text = it,
                style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 11.sp, fontWeight = FontWeight.Medium),
                maxLines = 1,
            )
        }
        if (section.chartType == ChartType.Bar && section.data.isNotEmpty()) {
            val maxV = section.data.maxOf { it.value }.coerceAtLeast(0.001)
            Row(
                modifier = GlanceModifier.fillMaxWidth().height(plotH.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                section.data.take(8).forEach { point ->
                    val h = ((point.value / maxV) * plotH).toFloat().coerceAtLeast(4f)
                    Box(
                        modifier = GlanceModifier
                            .defaultWeight()
                            .height(h.dp)
                            .padding(horizontal = 1.dp)
                            .background(ColorProvider(StyleTokens.plot)),
                    ) {}
                }
            }
        } else {
            Text(
                text = "${section.chartType.name.lowercase()} · ${section.data.size} points",
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun GlanceList(title: String?, items: List<ListItem>, size: CanvasSize) {
    Column {
        if (!title.isNullOrBlank()) {
            Text(
                text = title,
                style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 11.sp, fontWeight = FontWeight.Medium),
                maxLines = 1,
            )
        }
        items.forEach { item ->
            val prefix = item.icon?.let { "${it.plainGlyph()} " }.orEmpty()
            val suffix = item.badge?.takeIf { it.isNotBlank() }?.let { "  $it" }.orEmpty()
            Text(
                text = "$prefix${item.primary}$suffix",
                style = TextStyle(
                    color = toneProvider(item.tone, GlanceTheme.colors.onSurface),
                    fontSize = 11.sp,
                ),
                maxLines = 1,
            )
            if (size != CanvasSize.Small) {
                item.secondary?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        text = it,
                        style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

@Composable
private fun GlanceImage(section: CanvasSection.Image, size: CanvasSize) {
    val h = ContentClip.imageHeight(size, section.height)
    val bitmap = CanvasImages.decode(section.resolvedSource)
    if (bitmap != null) {
        Image(
            provider = ImageProvider(bitmap),
            contentDescription = section.caption ?: "Image",
            modifier = GlanceModifier.fillMaxWidth().height(h.dp),
            contentScale = ContentScale.Crop,
        )
    } else {
        Text(
            text = section.caption?.takeIf { it.isNotBlank() } ?: "Image unavailable",
            style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 10.sp),
            maxLines = 1,
        )
    }
}

@Composable
private fun toneProvider(tone: CanvasTone?, fallback: ColorProvider): ColorProvider {
    val color: Color? = StyleTokens.color(tone)
    return if (color != null) ColorProvider(color) else fallback
}
