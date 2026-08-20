package dev.velox.agentcanvas.canvas

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive

object CanvasParser {
    val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = false
        coerceInputValues = false
        explicitNulls = false
        classDiscriminator = "type"
    }

    fun parse(raw: String): CanvasDocument {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            throw CanvasParseException("Canvas JSON is empty")
        }
        val element: JsonElement = try {
            json.parseToJsonElement(trimmed)
        } catch (e: SerializationException) {
            throw CanvasParseException("Invalid canvas JSON: ${e.message}", e)
        }
        val obj = element as? JsonObject
            ?: throw CanvasParseException("Canvas JSON must be an object")
        val version = obj["version"]?.jsonPrimitive?.content?.toIntOrNull()
        if (version == null) {
            throw CanvasParseException("Missing required field: version")
        }
        if (version != 1) {
            throw CanvasParseException("Unsupported schema version $version (expected 1)")
        }
        if (!obj.containsKey("sections")) {
            throw CanvasParseException("Missing required field: sections")
        }
        return try {
            json.decodeFromJsonElement(CanvasDocument.serializer(), obj)
        } catch (e: SerializationException) {
            throw CanvasParseException("Invalid canvas JSON: ${e.message}", e)
        } catch (e: IllegalArgumentException) {
            throw CanvasParseException("Invalid canvas JSON: ${e.message}", e)
        }
    }

    fun parseOrNull(raw: String): Result<CanvasDocument> = runCatching { parse(raw) }
}
