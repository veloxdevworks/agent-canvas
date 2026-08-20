package dev.velox.agentcanvas.canvas

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class CanvasParserTest {
    @Test
    fun emptyFixtureIsEmptyCanvas() {
        val doc = CanvasParser.parse(readFixture("empty.json"))
        assertEquals(1, doc.version)
        assertTrue(doc.sections.isEmpty())
        assertTrue(doc.isEmptyContent)
    }

    @Test
    fun sampleMetricsParsesSections() {
        val doc = CanvasParser.parse(readFixture("sample-metrics.json"))
        assertEquals("Jira Throughput", doc.title)
        assertEquals(5, doc.sections.size)
        assertTrue(doc.sections[0] is CanvasSection.Header)
        assertTrue(doc.sections[1] is CanvasSection.Metrics)
        assertTrue(doc.sections[2] is CanvasSection.Chart)
        assertTrue(doc.sections[3] is CanvasSection.ListSection)
        assertTrue(doc.sections[4] is CanvasSection.Text)
    }

    @Test
    fun expressivenessParsesTonesAndDetailGroup() {
        val doc = CanvasParser.parse(readFixture("expressiveness.json"))
        val header = doc.sections.first() as CanvasSection.Header
        assertEquals(CanvasTone.Info, header.tone)
        assertEquals(IconName.Rocket, header.icon)
        val group = doc.detail?.sections?.firstOrNull { it is CanvasSection.Group } as CanvasSection.Group
        assertEquals(GroupDirection.Row, group.direction)
        assertEquals(3, group.children.size)
    }

    @Test
    fun actionsParseOnOpenAndListAction() {
        val doc = CanvasParser.parse(readFixture("actions.json"))
        assertEquals(CanvasAction.Expand, doc.onOpen)
        val list = doc.sections[1] as CanvasSection.ListSection
        assertTrue(list.items[0].action is CanvasAction.Url)
        assertTrue(list.items[1].action is CanvasAction.File)
    }

    @Test
    fun invalidJsonFailsClearly() {
        try {
            CanvasParser.parse("{not json")
            fail("expected CanvasParseException")
        } catch (e: CanvasParseException) {
            assertTrue(e.message!!.contains("Invalid canvas JSON"))
        }
    }

    @Test
    fun unsupportedVersionFails() {
        try {
            CanvasParser.parse("""{"version":2,"sections":[]}""")
            fail("expected CanvasParseException")
        } catch (e: CanvasParseException) {
            assertTrue(e.message!!.contains("Unsupported schema version"))
        }
    }

    @Test
    fun allBundledFixturesParse() {
        Fixtures.catalog.forEach { fixture ->
            val doc = CanvasParser.parse(readFixture(fixture.fileName))
            assertEquals(fixture.fileName, 1, doc.version)
        }
    }

    private fun readFixture(name: String): String {
        val candidates = listOf(
            File("src/main/assets/fixtures/$name"),
            File("app/src/main/assets/fixtures/$name"),
        )
        val file = candidates.firstOrNull { it.isFile }
            ?: error("Missing fixture $name (looked in ${candidates.joinToString()})")
        return file.readText()
    }
}
