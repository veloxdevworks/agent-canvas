package dev.velox.agentcanvas.canvas

import android.content.Context

data class BundledFixture(
    val fileName: String,
    val label: String,
    val summary: String,
)

object Fixtures {
    val catalog: List<BundledFixture> = listOf(
        BundledFixture("empty.json", "empty", "Empty canvas"),
        BundledFixture("sample-metrics.json", "sample-metrics", "Jira throughput"),
        BundledFixture("demo-sm-one.json", "demo-sm-one", "Build metrics"),
        BundledFixture("demo-md-one.json", "demo-md-one", "Sprint pulse"),
        BundledFixture("demo-md-two.json", "demo-md-two", "Traffic mix"),
        BundledFixture("demo-lg-one.json", "demo-lg-one", "Jira throughput (large)"),
        BundledFixture("demo-lg-two.json", "demo-lg-two", "PR queue"),
        BundledFixture("demo-xl-one.json", "demo-xl-one", "Platform health"),
        BundledFixture("expressiveness.json", "expressiveness", "Tones, badges, progress"),
        BundledFixture("actions.json", "actions", "List actions (no-op in this slice)"),
        BundledFixture("cover.json", "cover", "Full-bleed cover"),
    )

    fun loadRaw(context: Context, fileName: String): String {
        return context.assets.open("fixtures/$fileName").bufferedReader().use { it.readText() }
    }

    fun loadDocument(context: Context, fileName: String): CanvasDocument {
        return CanvasParser.parse(loadRaw(context, fileName))
    }
}
