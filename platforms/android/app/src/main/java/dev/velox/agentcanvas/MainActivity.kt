package dev.velox.agentcanvas

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dev.velox.agentcanvas.ui.HostScreen
import dev.velox.agentcanvas.ui.theme.AgentCanvasTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AgentCanvasTheme {
                HostScreen()
            }
        }
    }
}
