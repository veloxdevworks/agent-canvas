package dev.velox.agentcanvas.widget

import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.updateAll
import dev.velox.agentcanvas.canvas.CanvasDefinition

object DefinitionWidgets {
    fun widget(definition: CanvasDefinition): GlanceAppWidget = when (definition) {
        CanvasDefinition.One -> OneWidget()
        CanvasDefinition.Two -> TwoWidget()
        CanvasDefinition.Three -> ThreeWidget()
        CanvasDefinition.Four -> FourWidget()
        CanvasDefinition.Five -> FiveWidget()
        CanvasDefinition.Six -> SixWidget()
        CanvasDefinition.Seven -> SevenWidget()
        CanvasDefinition.Eight -> EightWidget()
        CanvasDefinition.Nine -> NineWidget()
        CanvasDefinition.Ten -> TenWidget()
        CanvasDefinition.Eleven -> ElevenWidget()
        CanvasDefinition.Twelve -> TwelveWidget()
    }

    suspend fun update(context: Context, definition: CanvasDefinition) {
        widget(definition).updateAll(context)
    }

    suspend fun updateAllDefinitions(context: Context) {
        CanvasDefinition.all.forEach { update(context, it) }
    }
}
