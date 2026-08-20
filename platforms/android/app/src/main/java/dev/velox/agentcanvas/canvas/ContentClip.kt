package dev.velox.agentcanvas.canvas

/**
 * Priority + height packing — port of Apple `ContentClip`.
 * Shared by Compose preview and Glance widgets.
 */
object ContentClip {
    data class Result(
        val shown: List<CanvasSection>,
        val shownIndices: List<Int>,
        val droppedTypes: List<String>,
        val truncated: Boolean,
        val listItemsShown: Int,
        val listItemsTotal: Int,
        val chartHeightScale: Float = 1f,
        val cover: Boolean = false,
    )

    fun imageHeight(size: CanvasSize, height: ImageHeight?): Float {
        val spec = LayoutSpec.size(size)
        return when (height ?: ImageHeight.default) {
            ImageHeight.Small -> spec.imageHeightSmall
            ImageHeight.Medium -> spec.imageHeightMedium
            ImageHeight.Large -> spec.imageHeightLarge
        }
    }

    fun listItemCap(size: CanvasSize): Int = LayoutSpec.size(size).listItemCap

    fun maxCharts(size: CanvasSize): Int = LayoutSpec.size(size).maxCharts

    fun edgeInset(size: CanvasSize): Float = LayoutSpec.size(size).edgeInset

    fun chartPlotHeight(size: CanvasSize, scale: Float = 1f): Float {
        val base = LayoutSpec.size(size).chartPlotHeight
        return maxOf(22f, base * scale)
    }

    fun chartHeightScale(size: CanvasSize): Float = LayoutSpec.size(size).chartHeightScale

    fun listRowHeight(size: CanvasSize): Float = LayoutSpec.size(size).listRowHeight

    fun listSectionHeight(title: String?, rows: Int, size: CanvasSize): Float {
        val spec = LayoutSpec.size(size)
        val titleH = if (!title.isNullOrEmpty()) spec.listTitleHeight else 0f
        val blocks = (if (titleH > 0) 1 else 0) + rows
        val spacing = if (blocks > 1) (blocks - 1) * 3f else 0f
        return titleH + rows * spec.listRowHeight + spacing
    }

    fun estimatedHeight(
        section: CanvasSection,
        size: CanvasSize,
        chartScale: Float? = null,
    ): Float {
        val spec = LayoutSpec.size(size)
        return when (section) {
            is CanvasSection.Header ->
                if (section.subtitle == null) spec.headerHeightNoSubtitle else spec.headerHeightWithSubtitle
            is CanvasSection.Metrics -> spec.metricsHeight
            is CanvasSection.Chart -> {
                val scale = chartScale ?: spec.chartHeightScale
                val plot = chartPlotHeight(size, scale)
                val titleH = if (!section.title.isNullOrEmpty()) 12f else 0f
                val gap = if (titleH > 0) 2f else 0f
                titleH + gap + plot
            }
            is CanvasSection.ListSection ->
                listSectionHeight(section.title, section.items.size, size)
            is CanvasSection.Text -> spec.textHeight
            is CanvasSection.Image -> imageHeight(size, section.height)
            is CanvasSection.Spacer -> section.size?.gapPoints ?: spec.spacerHeight
            is CanvasSection.Progress -> spec.progressHeight
            is CanvasSection.Divider -> spec.dividerHeight
            is CanvasSection.KeyValue -> {
                val n = maxOf(section.items.size, 1).toFloat()
                n * spec.keyValueRowHeight + maxOf(n - 1, 0f) * 2f
            }
            is CanvasSection.Badges -> spec.badgesHeight
            is CanvasSection.Icon -> iconHeight(size, section.size)
            is CanvasSection.Group -> {
                val heights = section.children.map { estimatedHeight(it, size) }
                val gapPts = section.gap?.gapPoints ?: 4f
                when (section.direction) {
                    GroupDirection.Row -> heights.maxOrNull() ?: 0f
                    GroupDirection.Column -> {
                        val sum = heights.sum()
                        val gaps = if (section.children.size > 1) (section.children.size - 1) * gapPts else 0f
                        sum + gaps
                    }
                }
            }
        }
    }

    fun iconHeight(layout: CanvasSize, size: IconSize?): Float {
        val spec = LayoutSpec.size(layout)
        return when (size ?: IconSize.default) {
            IconSize.Sm -> spec.iconHeightSm
            IconSize.Md -> spec.iconHeightMd
            IconSize.Lg -> spec.iconHeightLg
        }
    }

    fun chromeHeight(
        hasTitle: Boolean,
        showOverflow: Boolean,
        hasTimestamp: Boolean,
        size: CanvasSize = CanvasSize.Medium,
        spacing: Float? = null,
    ): Float {
        val spec = LayoutSpec.size(size)
        val gap = spacing ?: if (size == CanvasSize.Medium) 4f else 6f
        var h = 0f
        if (hasTitle) h += spec.titleChromeHeight + gap
        var footerBlocks = 0
        if (showOverflow) {
            h += spec.overflowLineHeight
            footerBlocks += 1
        }
        if (hasTimestamp) {
            h += spec.timestampHeight
            footerBlocks += 1
        }
        if (footerBlocks > 1) h += 3f
        if (footerBlocks > 0) h += 3f
        return h
    }

    fun defaultTileWidth(size: CanvasSize): Float = LayoutSpec.size(size).tileWidth

    fun defaultTileHeight(size: CanvasSize): Float = LayoutSpec.size(size).tileHeight

    fun contentBudget(
        displayHeight: Float,
        size: CanvasSize,
        hasTitle: Boolean,
        hasTimestamp: Boolean,
        reserveOverflowLine: Boolean = true,
    ): Float {
        val tileH = if (displayHeight > 1f) displayHeight else defaultTileHeight(size)
        val inset = edgeInset(size) * 2f
        val chrome = chromeHeight(
            hasTitle = hasTitle,
            showOverflow = reserveOverflowLine,
            hasTimestamp = hasTimestamp,
            size = size,
        )
        return maxOf(48f, tileH - inset - chrome)
    }

    fun apply(
        document: CanvasDocument,
        size: CanvasSize,
        maxHeight: Float? = null,
    ): Result {
        if (document.cover != null) {
            return Result(
                shown = emptyList(),
                shownIndices = emptyList(),
                droppedTypes = emptyList(),
                truncated = false,
                listItemsShown = 0,
                listItemsTotal = 0,
                chartHeightScale = 1f,
                cover = true,
            )
        }

        val spec = LayoutSpec.size(size)
        val budget = maxHeight ?: contentBudget(
            displayHeight = defaultTileHeight(size),
            size = size,
            hasTitle = true,
            hasTimestamp = true,
            reserveOverflowLine = true,
        )
        val candidates = prioritizedCandidates(document, size)
        val spacing = spec.sectionSpacing

        val packed = linkedMapOf<Int, CanvasSection>()
        val chartScales = mutableMapOf<Int, Float>()
        var used = 0f
        var listShown = 0
        var listTotal = 0

        for ((index, section) in candidates) {
            if (packed.containsKey(index)) continue
            val gap = if (packed.isEmpty()) 0f else spacing
            val remaining = budget - used - gap
            if (remaining < 8f) break

            if (section is CanvasSection.ListSection) {
                listTotal = maxOf(listTotal, section.items.size)
                val effectiveTitle = if (size == CanvasSize.Small) null else section.title
                val fit = fitList(effectiveTitle, section.items, section.priority, size, remaining)
                if (fit != null) {
                    packed[index] = fit.section
                    used += gap + fit.height
                    listShown = maxOf(listShown, fit.rows)
                }
                continue
            }

            val clipped = if (
                (size == CanvasSize.Small || size == CanvasSize.Medium) &&
                section is CanvasSection.Header
            ) {
                val keepSub = when {
                    size == CanvasSize.Medium &&
                        !section.subtitle.isNullOrEmpty() &&
                        section.subtitle.length <= 36 -> section.subtitle
                    else -> null
                }
                section.copy(subtitle = if (size == CanvasSize.Small) null else keepSub)
            } else {
                clipNonList(section, size)
            }

            if (clipped is CanvasSection.Chart) {
                val fit = fitChart(clipped, size, remaining)
                if (fit != null) {
                    packed[index] = fit.section
                    chartScales[index] = fit.scale
                    used += gap + fit.height
                }
                continue
            }

            val h = estimatedHeight(clipped, size)
            if (h > remaining) continue
            packed[index] = clipped
            used += gap + h
        }

        if (used < budget) {
            document.sections.forEachIndexed { index, section ->
                if (packed.containsKey(index)) return@forEachIndexed
                if (section !is CanvasSection.ListSection) return@forEachIndexed
                val gap = if (packed.isEmpty()) 0f else spacing
                val remaining = budget - used - gap
                listTotal = maxOf(listTotal, section.items.size)
                val effectiveTitle = if (size == CanvasSize.Small) null else section.title
                val fit = fitList(effectiveTitle, section.items, section.priority, size, remaining)
                if (fit != null) {
                    packed[index] = fit.section
                    used += gap + fit.height
                    listShown = maxOf(listShown, fit.rows)
                }
            }
        }

        if (used < budget) {
            document.sections.forEachIndexed { index, section ->
                if (packed.containsKey(index)) return@forEachIndexed
                if (section !is CanvasSection.Chart) return@forEachIndexed
                val gap = if (packed.isEmpty()) 0f else spacing
                val remaining = budget - used - gap
                val clipped = clipNonList(section, size)
                val fit = fitChart(clipped, size, remaining)
                if (fit != null) {
                    packed[index] = fit.section
                    chartScales[index] = fit.scale
                    used += gap + fit.height
                }
            }
        }

        if (listShown == 0) {
            document.sections.forEachIndexed { index, section ->
                if (section is CanvasSection.ListSection) {
                    val first = section.items.firstOrNull() ?: return@forEachIndexed
                    listTotal = maxOf(listTotal, section.items.size)
                    packed[index] = section.copy(
                        title = if (size == CanvasSize.Small) null else section.title,
                        items = listOf(first),
                    )
                    listShown = 1
                    return@forEachIndexed
                }
            }
        }

        if (packed.isEmpty()) {
            document.sections.firstOrNull()?.let { packed[0] = clipNonList(it, size) }
        }

        val ordered = mutableListOf<CanvasSection>()
        val orderedIndices = mutableListOf<Int>()
        val dropped = mutableListOf<String>()
        var minChartScale: Float? = null
        document.sections.forEachIndexed { i, section ->
            val shown = packed[i]
            if (shown != null) {
                ordered += shown
                orderedIndices += i
                chartScales[i]?.let { s ->
                    minChartScale = minOf(minChartScale ?: s, s)
                }
            } else {
                dropped += section.typeName
                if (section is CanvasSection.ListSection) {
                    listTotal = maxOf(listTotal, section.items.size)
                }
            }
        }

        val truncated = dropped.isNotEmpty() || listTotal > listShown
        return Result(
            shown = ordered,
            shownIndices = orderedIndices,
            droppedTypes = dropped,
            truncated = truncated,
            listItemsShown = listShown,
            listItemsTotal = listTotal,
            chartHeightScale = minChartScale ?: chartHeightScale(size),
        )
    }

    fun overflowCaption(clip: Result, size: CanvasSize): String {
        if (clip.listItemsTotal > clip.listItemsShown && clip.listItemsShown > 0) {
            return "+${clip.listItemsTotal - clip.listItemsShown} more in list"
        }
        if (clip.droppedTypes.isNotEmpty()) {
            val types = clip.droppedTypes.joinToString(", ")
            return "+${clip.droppedTypes.size} more hidden ($types)"
        }
        if (clip.listItemsTotal > clip.listItemsShown) {
            return "+${clip.listItemsTotal - clip.listItemsShown} more in list"
        }
        return "Content clipped for ${size.id}"
    }

    fun showsDocumentTitle(document: CanvasDocument, size: CanvasSize): Boolean {
        if (size == CanvasSize.Small) return false
        val title = document.title?.takeIf { it.isNotBlank() } ?: return false
        val first = document.sections.firstOrNull()
        if (first is CanvasSection.Header) {
            val text = first.text
            if (title.contains(text, ignoreCase = true) || text.contains(title, ignoreCase = true)) {
                return false
            }
        }
        return true
    }

    private data class ChartFit(val section: CanvasSection, val height: Float, val scale: Float)

    private fun fitChart(section: CanvasSection, size: CanvasSize, maxHeight: Float): ChartFit? {
        val chart = section as? CanvasSection.Chart ?: return null
        val base = chartHeightScale(size)
        val scales = listOf(base, base * 0.85f, base * 0.7f, base * 0.55f, 0.5f, 0.4f)
        val variants = listOf(chart, chart.copy(title = null))
        for (variant in variants) {
            for (scale in scales) {
                val h = estimatedHeight(variant, size, scale)
                if (h <= maxHeight) return ChartFit(variant, h, scale)
            }
        }
        return null
    }

    private data class ListFit(val section: CanvasSection, val height: Float, val rows: Int)

    private fun fitList(
        title: String?,
        items: List<ListItem>,
        priority: Int?,
        size: CanvasSize,
        maxHeight: Float,
    ): ListFit? {
        if (items.isEmpty()) return null
        val cap = minOf(listItemCap(size), items.size)

        fun best(sectionTitle: String?): ListFit? {
            var bestRows = 0
            var bestH = 0f
            for (rows in 1..cap) {
                val h = listSectionHeight(sectionTitle, rows, size)
                if (h <= maxHeight) {
                    bestRows = rows
                    bestH = h
                } else {
                    break
                }
            }
            if (bestRows == 0) return null
            return ListFit(
                section = CanvasSection.ListSection(
                    title = sectionTitle,
                    items = items.take(bestRows),
                    priority = priority,
                ),
                height = bestH,
                rows = bestRows,
            )
        }

        val without = best(null)
        val with = if (title != null) best(title) else null
        return when {
            with != null && without != null -> if (without.rows > with.rows) without else with
            else -> with ?: without
        }
    }

    private fun prioritizedCandidates(
        document: CanvasDocument,
        size: CanvasSize,
    ): List<Pair<Int, CanvasSection>> {
        val chartCap = maxCharts(size)
        val indexed = document.sections.mapIndexed { i, s -> i to s }
            .sortedWith(compareBy<Pair<Int, CanvasSection>> { LayoutSpec.packRank[it.second.typeName] ?: 7 }.thenBy { it.first })
        var charts = 0
        val result = mutableListOf<Pair<Int, CanvasSection>>()
        for (pair in indexed) {
            if (pair.second is CanvasSection.Chart) {
                if (charts >= chartCap) continue
                charts += 1
            }
            result += pair
        }
        return result
    }

    private fun clipNonList(section: CanvasSection, size: CanvasSize): CanvasSection {
        val spec = LayoutSpec.size(size)
        return when (section) {
            is CanvasSection.Chart -> {
                val lim = when (size) {
                    CanvasSize.Small -> 5
                    CanvasSize.Medium -> 8
                    CanvasSize.Large -> 12
                }
                section.copy(data = section.data.take(lim))
            }
            is CanvasSection.Metrics -> {
                val lim = if (size == CanvasSize.Small) 2 else minOf(4, spec.maxMetrics)
                section.copy(items = section.items.take(lim))
            }
            is CanvasSection.Text -> {
                val lim = spec.maxTextChars
                if (section.content.length <= lim) section
                else section.copy(content = section.content.take(lim) + "…")
            }
            is CanvasSection.ListSection -> {
                section.copy(items = section.items.take(listItemCap(size)))
            }
            else -> section
        }
    }
}
