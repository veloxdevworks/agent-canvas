package dev.velox.agentcanvas.ui.preview

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.velox.agentcanvas.canvas.CanvasSize
import dev.velox.agentcanvas.canvas.ChartPoint
import dev.velox.agentcanvas.canvas.ChartType
import dev.velox.agentcanvas.canvas.ContentClip
import dev.velox.agentcanvas.canvas.StyleTokens
import kotlin.math.max
import kotlin.math.min

@Composable
fun ComposeChart(
    chartType: ChartType,
    title: String?,
    data: List<ChartPoint>,
    size: CanvasSize,
    heightScale: Float,
    modifier: Modifier = Modifier,
) {
    val cap = when (size) {
        CanvasSize.Small -> 5
        CanvasSize.Medium -> 8
        CanvasSize.Large -> 12
    }
    val points = data.take(cap)
    val plotH = ContentClip.chartPlotHeight(size, heightScale)
    val muted = MaterialTheme.colorScheme.onSurfaceVariant

    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        if (!title.isNullOrBlank()) {
            Text(
                text = title,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (points.isEmpty()) {
            Text("No chart data", style = MaterialTheme.typography.labelSmall, color = muted)
        } else {
            when (chartType) {
                ChartType.Bar -> BarChart(points, plotH, size != CanvasSize.Small)
                ChartType.Line -> LineChart(points, plotH)
                ChartType.Pie -> PieChart(points, plotH, showLegend = size == CanvasSize.Large)
                ChartType.Gauge -> GaugeChart(points, plotH)
            }
            Text(
                text = "${chartType.name.lowercase()} · ${points.size} points",
                fontSize = 9.sp,
                color = muted,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun BarChart(points: List<ChartPoint>, height: Float, showLabels: Boolean) {
    val maxV = max(points.maxOf { it.value }, 0.001)
    Column(Modifier.fillMaxWidth()) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(height.dp),
        ) {
            clipRect {
                val gap = 4.dp.toPx()
                val barW = (size.width - gap * (points.size + 1)) / points.size
                points.forEachIndexed { i, p ->
                    val h = (p.value / maxV).toFloat() * size.height * 0.92f
                    val x = gap + i * (barW + gap)
                    drawRect(
                        color = StyleTokens.plot,
                        topLeft = Offset(x, size.height - h),
                        size = Size(barW, h),
                    )
                }
            }
        }
        if (showLabels) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                points.forEach {
                    Text(
                        it.label,
                        fontSize = 8.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Clip,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun LineChart(points: List<ChartPoint>, height: Float) {
    val maxV = max(points.maxOf { it.value }, 0.001)
    val minV = min(points.minOf { it.value }, maxV)
    val span = max(maxV - minV, 0.001)
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(height.dp),
    ) {
        clipRect {
            if (points.isEmpty()) return@clipRect
            val path = Path()
            points.forEachIndexed { i, p ->
                val x = if (points.size == 1) size.width / 2f else i.toFloat() / (points.size - 1) * size.width
                val y = size.height - ((p.value - minV) / span).toFloat() * size.height * 0.9f - 2f
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            drawPath(path, StyleTokens.plot, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
            points.forEachIndexed { i, p ->
                val x = if (points.size == 1) size.width / 2f else i.toFloat() / (points.size - 1) * size.width
                val y = size.height - ((p.value - minV) / span).toFloat() * size.height * 0.9f - 2f
                drawCircle(StyleTokens.plot, radius = 3.dp.toPx(), center = Offset(x, y))
            }
        }
    }
}

@Composable
private fun PieChart(points: List<ChartPoint>, height: Float, showLegend: Boolean) {
    val total = max(points.sumOf { it.value }, 0.001)
    val colors = listOf(
        StyleTokens.plot,
        StyleTokens.plot.copy(alpha = 0.75f),
        StyleTokens.plot.copy(alpha = 0.55f),
        StyleTokens.plot.copy(alpha = 0.35f),
        StyleTokens.color(dev.velox.agentcanvas.canvas.CanvasTone.Info)!!,
    )
    Row(Modifier.fillMaxWidth().height(height.dp)) {
        Canvas(Modifier.weight(1f).height(height.dp)) {
            clipRect {
                var start = -90f
                val diameter = min(size.width, size.height)
                val topLeft = Offset((size.width - diameter) / 2f, (size.height - diameter) / 2f)
                points.forEachIndexed { i, p ->
                    val sweep = (p.value / total * 360.0).toFloat()
                    drawArc(
                        color = colors[i % colors.size],
                        startAngle = start,
                        sweepAngle = sweep,
                        useCenter = true,
                        topLeft = topLeft,
                        size = Size(diameter, diameter),
                    )
                    start += sweep
                }
            }
        }
        if (showLegend) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
                points.take(6).forEach {
                    Text(
                        "${it.label} ${it.value.toInt()}",
                        fontSize = 9.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
private fun GaugeChart(points: List<ChartPoint>, height: Float) {
    val value = points.firstOrNull()?.value ?: 0.0
    val maxV = points.getOrNull(1)?.value?.takeIf { it > 0 } ?: 100.0
    val frac = (value / maxV).toFloat().coerceIn(0f, 1f)
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(height.dp),
    ) {
        clipRect {
            val stroke = 8.dp.toPx()
            val diameter = min(size.width, size.height * 1.6f)
            val topLeft = Offset((size.width - diameter) / 2f, size.height - diameter / 2f - 4f)
            val arcSize = Size(diameter, diameter)
            drawArc(
                color = StyleTokens.previewLight,
                startAngle = 180f,
                sweepAngle = 180f,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(stroke, cap = StrokeCap.Round),
            )
            drawArc(
                color = StyleTokens.plot,
                startAngle = 180f,
                sweepAngle = 180f * frac,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(stroke, cap = StrokeCap.Round),
            )
        }
    }
}
