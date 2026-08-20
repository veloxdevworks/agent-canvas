package dev.velox.agentcanvas.store

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dev.velox.agentcanvas.canvas.CanvasDefinition
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.definitionDataStore by preferencesDataStore(name = "canvas_definitions")

data class DefinitionAssignment(
    val definition: CanvasDefinition,
    val fixtureFileName: String?,
)

class DefinitionStore(private val context: Context) {
    val assignments: Flow<Map<CanvasDefinition, String?>> = context.definitionDataStore.data.map { prefs ->
        CanvasDefinition.all.associateWith { definition ->
            prefs[key(definition)]?.takeIf { it.isNotBlank() }
        }
    }

    fun assignment(definition: CanvasDefinition): Flow<String?> =
        context.definitionDataStore.data.map { it[key(definition)]?.takeIf { name -> name.isNotBlank() } }

    suspend fun pin(definition: CanvasDefinition, fixtureFileName: String) {
        context.definitionDataStore.edit { prefs ->
            prefs[key(definition)] = fixtureFileName
        }
    }

    suspend fun clear(definition: CanvasDefinition) {
        context.definitionDataStore.edit { prefs ->
            prefs.remove(key(definition))
        }
    }

    companion object {
        fun key(definition: CanvasDefinition): Preferences.Key<String> =
            stringPreferencesKey("fixture_${definition.id}")
    }
}
