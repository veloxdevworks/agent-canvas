package dev.velox.agentcanvas.canvas

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ContentClipTest {
    @Test
    fun emptyDocumentIsNotTruncated() {
        val clip = ContentClip.apply(CanvasDocument(version = 1, sections = emptyList()), CanvasSize.Small)
        assertFalse(clip.truncated)
        assertTrue(clip.shown.isEmpty())
    }

    @Test
    fun coverSkipsSectionPacking() {
        val doc = CanvasDocument(
            version = 1,
            cover = CanvasCover(source = "asset:demo.png", alt = "Demo"),
            sections = listOf(CanvasSection.Header(text = "Hidden")),
        )
        val clip = ContentClip.apply(doc, CanvasSize.Medium)
        assertTrue(clip.cover)
        assertTrue(clip.shown.isEmpty())
    }

    @Test
    fun tightBudgetKeepsHeaderAndDropsChart() {
        val doc = CanvasDocument(
            version = 1,
            sections = listOf(
                CanvasSection.Header(text = "Hi"),
                CanvasSection.Chart(
                    chartType = ChartType.Bar,
                    title = "Bars",
                    data = listOf(ChartPoint("A", 1.0), ChartPoint("B", 2.0)),
                ),
            ),
        )
        val clip = ContentClip.apply(doc, CanvasSize.Small, maxHeight = 20f)
        assertTrue(clip.shown.any { it is CanvasSection.Header })
        assertTrue(clip.shown.none { it is CanvasSection.Chart })
        assertTrue(clip.truncated)
        assertTrue(clip.droppedTypes.contains("chart"))
    }

    @Test
    fun overflowCaptionForList() {
        val clip = ContentClip.Result(
            shown = emptyList(),
            shownIndices = emptyList(),
            droppedTypes = emptyList(),
            truncated = true,
            listItemsShown = 2,
            listItemsTotal = 5,
        )
        assertEquals("+3 more in list", ContentClip.overflowCaption(clip, CanvasSize.Medium))
    }
}
