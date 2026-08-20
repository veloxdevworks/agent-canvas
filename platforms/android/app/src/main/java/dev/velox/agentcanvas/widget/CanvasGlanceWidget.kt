package dev.velox.agentcanvas.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import dev.velox.agentcanvas.canvas.CanvasDefinition
import dev.velox.agentcanvas.canvas.CanvasDocument
import dev.velox.agentcanvas.canvas.Fixtures
import dev.velox.agentcanvas.store.DefinitionStore
import kotlinx.coroutines.flow.first

abstract class CanvasGlanceWidget : GlanceAppWidget() {
    abstract val definition: CanvasDefinition

    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val store = DefinitionStore(context)
        val fixtureName = store.assignment(definition).first()
        val document = loadAssigned(context, fixtureName)
        provideContent {
            GlanceTheme {
                GlanceCanvasTile(document = document, definition = definition)
            }
        }
    }

    companion object {
        fun loadAssigned(context: Context, fixtureName: String?): CanvasDocument {
            if (fixtureName.isNullOrBlank()) {
                return CanvasDocument(version = 1, sections = emptyList())
            }
            return try {
                Fixtures.loadDocument(context, fixtureName)
            } catch (e: Exception) {
                CanvasDocument(
                    version = 1,
                    title = "Invalid JSON",
                    sections = listOf(
                        dev.velox.agentcanvas.canvas.CanvasSection.Text(
                            content = e.message ?: "Invalid canvas JSON",
                            tone = dev.velox.agentcanvas.canvas.CanvasTone.Critical,
                        ),
                    ),
                )
            }
        }
    }
}

class OneWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.One
}

class TwoWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Two
}

class ThreeWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Three
}

class FourWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Four
}

class FiveWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Five
}

class SixWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Six
}

class SevenWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Seven
}

class EightWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Eight
}

class NineWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Nine
}

class TenWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Ten
}

class ElevenWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Eleven
}

class TwelveWidget : CanvasGlanceWidget() {
    override val definition = CanvasDefinition.Twelve
}

class OneWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = OneWidget()
}

class TwoWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TwoWidget()
}

class ThreeWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = ThreeWidget()
}

class FourWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = FourWidget()
}

class FiveWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = FiveWidget()
}

class SixWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = SixWidget()
}

class SevenWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = SevenWidget()
}

class EightWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = EightWidget()
}

class NineWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = NineWidget()
}

class TenWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TenWidget()
}

class ElevenWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = ElevenWidget()
}

class TwelveWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = TwelveWidget()
}
