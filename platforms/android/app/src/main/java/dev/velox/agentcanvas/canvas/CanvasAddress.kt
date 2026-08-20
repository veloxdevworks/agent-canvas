package dev.velox.agentcanvas.canvas

/** Compiled canvas identities: one through twelve (not size-baked). */
enum class CanvasDefinition(val id: String, val displayName: String, val ordinalLabel: String) {
    One("one", "One", "1"),
    Two("two", "Two", "2"),
    Three("three", "Three", "3"),
    Four("four", "Four", "4"),
    Five("five", "Five", "5"),
    Six("six", "Six", "6"),
    Seven("seven", "Seven", "7"),
    Eight("eight", "Eight", "8"),
    Nine("nine", "Nine", "9"),
    Ten("ten", "Ten", "10"),
    Eleven("eleven", "Eleven", "11"),
    Twelve("twelve", "Twelve", "12");

    /** Conceptual WidgetKit / Glance kind: AgentCanvas.one … AgentCanvas.twelve. */
    val widgetKind: String get() = "AgentCanvas.$id"

    companion object {
        val all: List<CanvasDefinition> = entries

        fun fromId(id: String): CanvasDefinition? = entries.firstOrNull { it.id == id }
    }
}

/** Glance / preview size chosen at placement — not part of the canvas identity. */
enum class CanvasSize(val id: String, val label: String) {
    Small("sm", "Small"),
    Medium("md", "Medium"),
    Large("lg", "Large");

    companion object {
        fun fromGlance(widthDp: Float, heightDp: Float): CanvasSize {
            return when {
                heightDp >= 240f -> Large
                widthDp >= 220f -> Medium
                else -> Small
            }
        }
    }
}
