package dev.velox.agentcanvas.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.velox.agentcanvas.canvas.BundledFixture
import dev.velox.agentcanvas.canvas.CanvasDefinition
import dev.velox.agentcanvas.canvas.CanvasDocument
import dev.velox.agentcanvas.canvas.CanvasParseException
import dev.velox.agentcanvas.canvas.CanvasParser
import dev.velox.agentcanvas.canvas.CanvasSize
import dev.velox.agentcanvas.canvas.ContentClip
import dev.velox.agentcanvas.canvas.Fixtures
import dev.velox.agentcanvas.store.DefinitionStore
import dev.velox.agentcanvas.ui.preview.ComposeCanvasTile
import dev.velox.agentcanvas.widget.DefinitionWidgets
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HostScreen() {
    val context = LocalContext.current
    val store = remember { DefinitionStore(context) }
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    var selectedFixture by remember { mutableStateOf(Fixtures.catalog.first()) }
    var selectedDefinition by remember { mutableStateOf(CanvasDefinition.One) }
    var selectedSize by remember { mutableStateOf(CanvasSize.Medium) }
    var document by remember { mutableStateOf<CanvasDocument?>(null) }
    var parseError by remember { mutableStateOf<String?>(null) }
    var pinnedName by remember { mutableStateOf<String?>(null) }

    fun loadFixture(fixture: BundledFixture) {
        try {
            document = CanvasParser.parse(Fixtures.loadRaw(context, fixture.fileName))
            parseError = null
        } catch (e: CanvasParseException) {
            document = null
            parseError = e.message ?: "Invalid canvas JSON"
        }
    }

    LaunchedEffect(selectedFixture) {
        loadFixture(selectedFixture)
    }
    LaunchedEffect(selectedDefinition) {
        pinnedName = store.assignment(selectedDefinition).first()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Agent Canvas") },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = "Fixtures only — no cloud, no sign-in. Size is chosen at placement.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Label("Size")
            ChipRow {
                CanvasSize.entries.forEach { size ->
                    FilterChip(
                        selected = selectedSize == size,
                        onClick = { selectedSize = size },
                        label = { Text(size.label) },
                    )
                }
            }

            Label("Definition")
            ChipRow {
                CanvasDefinition.all.forEach { definition ->
                    FilterChip(
                        selected = selectedDefinition == definition,
                        onClick = { selectedDefinition = definition },
                        label = { Text(definition.id) },
                    )
                }
            }
            Text(
                text = selectedDefinition.widgetKind,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Label("Fixture")
            ChipRow {
                Fixtures.catalog.forEach { fixture ->
                    FilterChip(
                        selected = selectedFixture.fileName == fixture.fileName,
                        onClick = { selectedFixture = fixture },
                        label = { Text(fixture.label) },
                    )
                }
            }
            Text(
                text = selectedFixture.summary,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = {
                        scope.launch {
                            store.pin(selectedDefinition, selectedFixture.fileName)
                            DefinitionWidgets.update(context, selectedDefinition)
                            pinnedName = selectedFixture.fileName
                            snackbar.showSnackbar(
                                "Pinned ${selectedFixture.label} to ${selectedDefinition.id}",
                            )
                        }
                    },
                ) {
                    Text("Pin to ${selectedDefinition.id}")
                }
                OutlinedButton(
                    onClick = {
                        scope.launch {
                            store.clear(selectedDefinition)
                            DefinitionWidgets.update(context, selectedDefinition)
                            pinnedName = null
                            snackbar.showSnackbar("Cleared ${selectedDefinition.id}")
                        }
                    },
                ) {
                    Text("Clear")
                }
            }
            Text(
                text = pinnedName?.let { "Widget ${selectedDefinition.id} shows $it" }
                    ?: "Widget ${selectedDefinition.id} is empty",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            HorizontalDivider()

            val spec = ContentClip
            Text(
                text = "Preview · ${selectedSize.label.lowercase()} · " +
                    "${spec.defaultTileWidth(selectedSize).toInt()}×${spec.defaultTileHeight(selectedSize).toInt()} dp",
                style = MaterialTheme.typography.titleSmall,
            )
            when {
                parseError != null -> {
                    Text(
                        text = parseError!!,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                document != null -> {
                    ComposeCanvasTile(
                        document = document!!,
                        size = selectedSize,
                        definition = selectedDefinition,
                    )
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun Label(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall)
}

@Composable
private fun ChipRow(content: @Composable () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        content()
        Spacer(Modifier.width(4.dp))
    }
}
