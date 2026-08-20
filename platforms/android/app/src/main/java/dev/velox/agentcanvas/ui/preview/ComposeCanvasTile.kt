package dev.velox.agentcanvas.ui.preview

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Help
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.InsertChart
import androidx.compose.material.icons.outlined.InsertDriveFile
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.RocketLaunch
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.velox.agentcanvas.canvas.BadgeItem
import dev.velox.agentcanvas.canvas.CanvasDefinition
import dev.velox.agentcanvas.canvas.CanvasDocument
import dev.velox.agentcanvas.canvas.CanvasEmphasis
import dev.velox.agentcanvas.canvas.CanvasImages
import dev.velox.agentcanvas.canvas.CanvasSection
import dev.velox.agentcanvas.canvas.CanvasSize
import dev.velox.agentcanvas.canvas.CanvasTone
import dev.velox.agentcanvas.canvas.ContentClip
import dev.velox.agentcanvas.canvas.CoverFit
import dev.velox.agentcanvas.canvas.GroupAlign
import dev.velox.agentcanvas.canvas.GroupDirection
import dev.velox.agentcanvas.canvas.IconName
import dev.velox.agentcanvas.canvas.IconSize
import dev.velox.agentcanvas.canvas.KeyValueItem
import dev.velox.agentcanvas.canvas.ListItem
import dev.velox.agentcanvas.canvas.MetricItem
import dev.velox.agentcanvas.canvas.SpacerSize
import dev.velox.agentcanvas.canvas.StyleTokens

@Composable
fun ComposeCanvasTile(
    document: CanvasDocument,
    size: CanvasSize,
    definition: CanvasDefinition,
    modifier: Modifier = Modifier,
    width: Dp = ContentClip.defaultTileWidth(size).dp,
    height: Dp = ContentClip.defaultTileHeight(size).dp,
) {
    val dark = isSystemInDarkTheme()
    val chrome = if (dark) StyleTokens.previewDark else StyleTokens.previewLight
    val radius = if (size == CanvasSize.Large) 24.dp else 22.dp
    val hasTitle = ContentClip.showsDocumentTitle(document, size)
    val hasTimestamp = !document.updatedAt.isNullOrBlank()
    var budget = ContentClip.contentBudget(
        displayHeight = height.value,
        size = size,
        hasTitle = hasTitle && !document.isEmptyContent,
        hasTimestamp = hasTimestamp && !document.isEmptyContent,
        reserveOverflowLine = false,
    )
    var clip = ContentClip.apply(document, size, budget)
    if (clip.truncated) {
        budget = ContentClip.contentBudget(
            displayHeight = height.value,
            size = size,
            hasTitle = hasTitle && !document.isEmptyContent,
            hasTimestamp = hasTimestamp && !document.isEmptyContent,
            reserveOverflowLine = true,
        )
        clip = ContentClip.apply(document, size, budget)
    }

    Box(
        modifier
            .size(width, height)
            .clip(RoundedCornerShape(radius))
            .background(chrome),
    ) {
        when {
            document.isEmptyContent -> EmptyCanvas(definition, size, fill = true)
            document.cover != null -> CoverOrFallback(document, size, clip, definition)
            else -> PackedContent(document, size, clip, fill = true)
        }
    }
}

@Composable
private fun CoverOrFallback(
    document: CanvasDocument,
    size: CanvasSize,
    clip: ContentClip.Result,
    definition: CanvasDefinition,
) {
    val cover = document.cover ?: return
    val bitmap = CanvasImages.decode(cover.source)
    if (bitmap != null) {
        val scale = if (cover.resolvedFit == CoverFit.Contain) ContentScale.Fit else ContentScale.Crop
        androidx.compose.foundation.Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = cover.alt,
            contentScale = scale,
            modifier = Modifier.fillMaxSize(),
        )
    } else {
        Column(
            Modifier
                .fillMaxSize()
                .padding(ContentClip.edgeInset(size).dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = if (cover.alt.isNotBlank()) cover.alt else "Cover unavailable",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            PackedContent(document.withoutCover, size, clipForFallback(document, size), fill = true)
        }
    }
}

private fun clipForFallback(document: CanvasDocument, size: CanvasSize): ContentClip.Result {
    val budget = ContentClip.contentBudget(
        displayHeight = ContentClip.defaultTileHeight(size) - 20f,
        size = size,
        hasTitle = false,
        hasTimestamp = false,
        reserveOverflowLine = true,
    )
    return ContentClip.apply(document.withoutCover, size, budget)
}

@Composable
private fun PackedContent(
    document: CanvasDocument,
    size: CanvasSize,
    clip: ContentClip.Result,
    fill: Boolean,
) {
    val inset = ContentClip.edgeInset(size).dp
    Column(
        Modifier
            .fillMaxSize()
            .padding(inset)
            .clip(RoundedCornerShape(0.dp)),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (ContentClip.showsDocumentTitle(document, size)) {
            Text(
                text = document.title.orEmpty(),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        clip.shown.forEach { section ->
            SectionView(section, size, clip)
        }
        if (fill) {
            Spacer(Modifier.weight(1f, fill = true))
        }
        if (clip.truncated) {
            Text(
                text = ContentClip.overflowCaption(clip, size),
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
                color = StyleTokens.overflow,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        document.updatedAt?.takeIf { it.isNotBlank() }?.let { stamp ->
            Text(
                text = "Updated $stamp",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun EmptyCanvas(definition: CanvasDefinition, size: CanvasSize, fill: Boolean) {
    val inset = ContentClip.edgeInset(size).dp
    Column(
        Modifier
            .fillMaxSize()
            .padding(inset),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Outlined.AutoAwesome,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(if (size == CanvasSize.Small) 28.dp else 32.dp),
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = "No content",
            style = if (size == CanvasSize.Small) MaterialTheme.typography.titleSmall else MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
        )
        Text(
            text = definition.displayName,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = if (size == CanvasSize.Small) 2 else 3,
        )
    }
}

@Composable
private fun SectionView(section: CanvasSection, size: CanvasSize, clip: ContentClip.Result) {
    when (section) {
        is CanvasSection.Header -> HeaderSection(section, size)
        is CanvasSection.Text -> TextSection(section, size)
        is CanvasSection.Metrics -> MetricsSection(section.items, size)
        is CanvasSection.Chart -> ComposeChart(
            chartType = section.chartType,
            title = section.title,
            data = section.data,
            size = size,
            heightScale = clip.chartHeightScale,
        )
        is CanvasSection.ListSection -> ListSectionView(section.title, section.items, size)
        is CanvasSection.Image -> ImageSection(section, size)
        is CanvasSection.Spacer -> Spacer(Modifier.height((section.size?.gapPoints ?: 4f).dp))
        is CanvasSection.Group -> GroupSection(section, size, clip)
        is CanvasSection.Progress -> ProgressSection(section, size)
        is CanvasSection.Divider -> Box(
            Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)),
        )
        is CanvasSection.KeyValue -> KeyValueSection(section.items)
        is CanvasSection.Badges -> BadgesSection(section.items)
        is CanvasSection.Icon -> IconLeaf(section.name, section.tone, section.size, size)
    }
}

@Composable
private fun HeaderSection(section: CanvasSection.Header, size: CanvasSize) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        section.icon?.let { IconGlyph(it, section.tone, if (size == CanvasSize.Small) 13.dp else 16.dp) }
        Column(Modifier.weight(1f)) {
            Text(
                text = section.text,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = if (section.emphasis == CanvasEmphasis.Strong) FontWeight.Bold else FontWeight.SemiBold,
                color = StyleTokens.foreground(section.tone, MaterialTheme.colorScheme.onSurface),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            section.subtitle?.takeIf { it.isNotBlank() }?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun TextSection(section: CanvasSection.Text, size: CanvasSize) {
    Text(
        text = section.content,
        style = MaterialTheme.typography.bodySmall,
        fontWeight = StyleTokens.fontWeight(section.emphasis),
        color = StyleTokens.foreground(section.tone, MaterialTheme.colorScheme.onSurface),
        maxLines = if (size == CanvasSize.Small) 2 else 3,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
private fun MetricsSection(items: List<MetricItem>, size: CanvasSize) {
    val visible = items.take(if (size == CanvasSize.Small) 2 else 4)
    val compact = size == CanvasSize.Small || size == CanvasSize.Medium
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(if (size == CanvasSize.Small) 6.dp else 10.dp)) {
        visible.forEach { item ->
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(0.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    item.icon?.let { IconGlyph(it, item.tone, 12.dp) }
                    Text(
                        text = item.value,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = StyleTokens.foreground(item.tone, MaterialTheme.colorScheme.onSurface),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (compact) {
                        item.trend?.takeIf { it.isNotBlank() }?.let { trend ->
                            Text(
                                text = trend,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = StyleTokens.trendColor(trend, item.tone),
                                maxLines = 1,
                            )
                        }
                    }
                }
                Text(
                    text = item.label,
                    fontSize = 10.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (!compact) {
                    item.trend?.takeIf { it.isNotBlank() }?.let { trend ->
                        Text(
                            text = trend,
                            fontSize = 10.sp,
                            color = StyleTokens.trendColor(trend, item.tone),
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ListSectionView(title: String?, items: List<ListItem>, size: CanvasSize) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        if (!title.isNullOrBlank()) {
            Text(
                text = title,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        items.forEach { item ->
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                item.icon?.let { IconGlyph(it, item.tone, 12.dp) }
                Column(Modifier.weight(1f)) {
                    Text(
                        text = item.primary,
                        style = MaterialTheme.typography.bodySmall,
                        fontWeight = StyleTokens.fontWeight(item.emphasis),
                        color = StyleTokens.foreground(item.tone, MaterialTheme.colorScheme.onSurface),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    item.secondary?.takeIf { it.isNotBlank() && size != CanvasSize.Small }?.let {
                        Text(
                            text = it,
                            fontSize = 10.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                item.badge?.takeIf { it.isNotBlank() }?.let {
                    Text(
                        text = it,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

@Composable
private fun ImageSection(section: CanvasSection.Image, size: CanvasSize) {
    val h = ContentClip.imageHeight(size, section.height).dp
    val bitmap = CanvasImages.decode(section.resolvedSource)
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        if (bitmap != null) {
            androidx.compose.foundation.Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = section.caption ?: "Image",
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(h)
                    .clip(RoundedCornerShape(6.dp)),
            )
        } else {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(h)
                    .clip(RoundedCornerShape(6.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = section.caption?.takeIf { it.isNotBlank() } ?: "Image unavailable",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        section.caption?.takeIf { it.isNotBlank() && bitmap != null }?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun GroupSection(section: CanvasSection.Group, size: CanvasSize, clip: ContentClip.Result) {
    val gap = (section.gap?.gapPoints ?: SpacerSize.Md.gapPoints).dp
    val alignment = when (section.align) {
        GroupAlign.Center -> Alignment.CenterVertically
        GroupAlign.End -> Alignment.Bottom
        else -> Alignment.Top
    }
    when (section.direction) {
        GroupDirection.Row -> Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(gap),
            verticalAlignment = alignment,
        ) {
            section.children.forEach { child ->
                Box(Modifier.weight(1f)) { SectionView(child, size, clip) }
            }
        }
        GroupDirection.Column -> Column(verticalArrangement = Arrangement.spacedBy(gap)) {
            section.children.forEach { child -> SectionView(child, size, clip) }
        }
    }
}

@Composable
private fun ProgressSection(section: CanvasSection.Progress, size: CanvasSize) {
    val max = section.max?.takeIf { it > 0 } ?: 1.0
    val frac = (section.value / max).toFloat().coerceIn(0f, 1f)
    val color = StyleTokens.color(section.tone) ?: MaterialTheme.colorScheme.primary
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        section.label?.takeIf { it.isNotBlank() }?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.labelSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        LinearProgressIndicator(
            progress = { frac },
            modifier = Modifier.fillMaxWidth().height(if (size == CanvasSize.Small) 4.dp else 6.dp),
            color = color,
            trackColor = MaterialTheme.colorScheme.surfaceVariant,
        )
    }
}

@Composable
private fun KeyValueSection(items: List<KeyValueItem>) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        items.forEach { item ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    item.key,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    item.value,
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Medium,
                    color = StyleTokens.foreground(item.tone, MaterialTheme.colorScheme.onSurface),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BadgesSection(items: List<BadgeItem>) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        items.take(12).forEach { badge ->
            val tone = StyleTokens.color(badge.tone) ?: MaterialTheme.colorScheme.onSurfaceVariant
            Text(
                text = badge.text,
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium,
                color = tone,
                maxLines = 1,
                modifier = Modifier
                    .clip(RoundedCornerShape(4.dp))
                    .background(tone.copy(alpha = 0.12f))
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
private fun IconLeaf(name: IconName, tone: CanvasTone?, iconSize: IconSize?, size: CanvasSize) {
    val h = ContentClip.iconHeight(size, iconSize).dp
    IconGlyph(name, tone, h)
}

@Composable
private fun IconGlyph(name: IconName, tone: CanvasTone?, size: Dp) {
    Icon(
        imageVector = name.vector(),
        contentDescription = name.name.lowercase(),
        tint = StyleTokens.foreground(tone, MaterialTheme.colorScheme.onSurfaceVariant),
        modifier = Modifier.size(size),
    )
}

private fun IconName.vector() = when (this) {
    IconName.Check -> Icons.Outlined.CheckCircle
    IconName.Close -> Icons.Outlined.Close
    IconName.Warning, IconName.Alert -> Icons.Outlined.Warning
    IconName.Info -> Icons.Outlined.Info
    IconName.Help -> Icons.Outlined.Help
    IconName.Sparkle -> Icons.Outlined.AutoAwesome
    IconName.Search -> Icons.Outlined.Search
    IconName.Link -> Icons.Outlined.Link
    IconName.Copy -> Icons.Outlined.ContentCopy
    IconName.Refresh -> Icons.Outlined.Refresh
    IconName.Play -> Icons.Outlined.PlayArrow
    IconName.Pause -> Icons.Outlined.Pause
    IconName.Stop -> Icons.Outlined.Stop
    IconName.Rocket -> Icons.Outlined.RocketLaunch
    IconName.Bug -> Icons.Outlined.BugReport
    IconName.Clock -> Icons.Outlined.Schedule
    IconName.Calendar -> Icons.Outlined.CalendarMonth
    IconName.Person -> Icons.Outlined.Person
    IconName.People -> Icons.Outlined.People
    IconName.Folder -> Icons.Outlined.Folder
    IconName.File -> Icons.Outlined.InsertDriveFile
    IconName.Image -> Icons.Outlined.Image
    IconName.Chart -> Icons.Outlined.InsertChart
    IconName.Settings -> Icons.Outlined.Settings
    IconName.Lock -> Icons.Outlined.Lock
    IconName.Key -> Icons.Outlined.Key
    IconName.Cloud -> Icons.Outlined.Cloud
    IconName.Server -> Icons.Outlined.Dns
    IconName.Database -> Icons.Outlined.Storage
}
