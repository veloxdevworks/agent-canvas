package dev.velox.agentcanvas.canvas

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

@Serializable
data class CanvasDocument(
    val version: Int,
    val updatedAt: String? = null,
    val title: String? = null,
    val cover: CanvasCover? = null,
    val onOpen: CanvasAction? = null,
    val sections: List<CanvasSection> = emptyList(),
    val detail: CanvasDetail? = null,
) {
    val isEmptyContent: Boolean
        get() = cover == null && sections.isEmpty() && title.isNullOrBlank()

    val withoutCover: CanvasDocument get() = copy(cover = null)
}

@Serializable
data class CanvasCover(
    val source: String,
    val alt: String,
    val fit: CoverFit? = null,
) {
    val resolvedFit: CoverFit get() = fit ?: CoverFit.Cover
}

@Serializable
enum class CoverFit {
    @SerialName("cover") Cover,
    @SerialName("contain") Contain,
}

@Serializable
enum class ImageHeight {
    @SerialName("small") Small,
    @SerialName("medium") Medium,
    @SerialName("large") Large,
    ;

    companion object {
        val default: ImageHeight = Medium
    }
}

@Serializable
data class CanvasDetail(
    val sections: List<CanvasSection> = emptyList(),
)

@Serializable(with = CanvasActionSerializer::class)
sealed class CanvasAction {
    data object Expand : CanvasAction()
    data class Url(val url: String) : CanvasAction()
    data class File(val path: String) : CanvasAction()
    data object Noop : CanvasAction()
}

object CanvasActionSerializer : KSerializer<CanvasAction> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("CanvasAction") {
        element<String>("type")
        element<String>("url", isOptional = true)
        element<String>("path", isOptional = true)
    }

    override fun deserialize(decoder: Decoder): CanvasAction {
        val json = (decoder as JsonDecoder).decodeJsonElement()
        val obj = json as? JsonObject
            ?: throw SerializationException("action must be an object")
        return when (obj["type"]?.jsonPrimitive?.contentOrNull) {
            "expand" -> CanvasAction.Expand
            "url" -> CanvasAction.Url(
                obj["url"]?.jsonPrimitive?.contentOrNull
                    ?: throw SerializationException("action.url requires url"),
            )
            "file" -> CanvasAction.File(
                obj["path"]?.jsonPrimitive?.contentOrNull
                    ?: throw SerializationException("action.file requires path"),
            )
            "noop" -> CanvasAction.Noop
            else -> throw SerializationException("Unknown action type: ${obj["type"]}")
        }
    }

    override fun serialize(encoder: Encoder, value: CanvasAction) {
        val json = encoder as JsonEncoder
        json.encodeJsonElement(
            buildJsonObject {
                when (value) {
                    CanvasAction.Expand -> put("type", "expand")
                    is CanvasAction.Url -> {
                        put("type", "url")
                        put("url", value.url)
                    }
                    is CanvasAction.File -> {
                        put("type", "file")
                        put("path", value.path)
                    }
                    CanvasAction.Noop -> put("type", "noop")
                }
            },
        )
    }
}

@Serializable
sealed class CanvasSection {
    abstract val priority: Int?

    val typeName: String
        get() = when (this) {
            is Header -> "header"
            is Text -> "text"
            is Metrics -> "metrics"
            is Chart -> "chart"
            is ListSection -> "list"
            is Image -> "image"
            is Spacer -> "spacer"
            is Group -> "group"
            is Progress -> "progress"
            is Divider -> "divider"
            is KeyValue -> "keyValue"
            is Badges -> "badges"
            is Icon -> "icon"
        }

    val sortPriority: Int
        get() = priority ?: LayoutSpec.dropPriority[typeName] ?: 100

    @Serializable
    @SerialName("header")
    data class Header(
        val text: String,
        val subtitle: String? = null,
        val icon: IconName? = null,
        val tone: CanvasTone? = null,
        val emphasis: CanvasEmphasis? = null,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("text")
    data class Text(
        val content: String,
        val tone: CanvasTone? = null,
        val emphasis: CanvasEmphasis? = null,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("metrics")
    data class Metrics(
        val items: List<MetricItem>,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("chart")
    data class Chart(
        val chartType: ChartType,
        val title: String? = null,
        val data: List<ChartPoint>,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("list")
    data class ListSection(
        val title: String? = null,
        val items: List<ListItem>,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("image")
    data class Image(
        val source: String? = null,
        val url: String? = null,
        val caption: String? = null,
        val height: ImageHeight? = null,
        override val priority: Int? = null,
    ) : CanvasSection() {
        val resolvedSource: String
            get() = source?.takeIf { it.isNotBlank() } ?: url.orEmpty()
    }

    @Serializable
    @SerialName("spacer")
    data class Spacer(
        val size: SpacerSize? = null,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("group")
    data class Group(
        val direction: GroupDirection,
        val gap: SpacerSize? = null,
        val align: GroupAlign? = null,
        val children: List<CanvasSection>,
        val weight: Int? = null,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("progress")
    data class Progress(
        val label: String? = null,
        val value: Double,
        val max: Double? = null,
        val tone: CanvasTone? = null,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("divider")
    data class Divider(
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("keyValue")
    data class KeyValue(
        val items: List<KeyValueItem>,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("badges")
    data class Badges(
        val items: List<BadgeItem>,
        override val priority: Int? = null,
    ) : CanvasSection()

    @Serializable
    @SerialName("icon")
    data class Icon(
        val name: IconName,
        val tone: CanvasTone? = null,
        val size: IconSize? = null,
        override val priority: Int? = null,
    ) : CanvasSection()
}

@Serializable
data class MetricItem(
    val label: String,
    val value: String,
    val trend: String? = null,
    val icon: IconName? = null,
    val tone: CanvasTone? = null,
    val emphasis: CanvasEmphasis? = null,
)

@Serializable
enum class ChartType {
    @SerialName("bar") Bar,
    @SerialName("line") Line,
    @SerialName("pie") Pie,
    @SerialName("gauge") Gauge,
}

@Serializable
data class ChartPoint(
    val label: String,
    val value: Double,
)

@Serializable
data class ListItem(
    val primary: String,
    val secondary: String? = null,
    val badge: String? = null,
    val icon: IconName? = null,
    val action: CanvasAction? = null,
    val tone: CanvasTone? = null,
    val emphasis: CanvasEmphasis? = null,
)

@Serializable
data class KeyValueItem(
    val key: String,
    val value: String,
    val tone: CanvasTone? = null,
)

@Serializable
data class BadgeItem(
    val text: String,
    val tone: CanvasTone? = null,
)

@Serializable
enum class SpacerSize {
    @SerialName("sm") Sm,
    @SerialName("md") Md,
    @SerialName("lg") Lg,
    ;

    val gapPoints: Float
        get() = when (this) {
            Sm -> 4f
            Md -> 8f
            Lg -> 12f
        }
}

@Serializable
enum class GroupDirection {
    @SerialName("row") Row,
    @SerialName("column") Column,
}

@Serializable
enum class GroupAlign {
    @SerialName("start") Start,
    @SerialName("center") Center,
    @SerialName("end") End,
    @SerialName("stretch") Stretch,
}

@Serializable
enum class CanvasTone {
    @SerialName("critical") Critical,
    @SerialName("warning") Warning,
    @SerialName("success") Success,
    @SerialName("info") Info,
    @SerialName("muted") Muted,
}

@Serializable
enum class CanvasEmphasis {
    @SerialName("strong") Strong,
    @SerialName("normal") Normal,
    @SerialName("subtle") Subtle,
}

@Serializable
enum class IconName {
    @SerialName("check") Check,
    @SerialName("close") Close,
    @SerialName("warning") Warning,
    @SerialName("alert") Alert,
    @SerialName("info") Info,
    @SerialName("help") Help,
    @SerialName("sparkle") Sparkle,
    @SerialName("search") Search,
    @SerialName("link") Link,
    @SerialName("copy") Copy,
    @SerialName("refresh") Refresh,
    @SerialName("play") Play,
    @SerialName("pause") Pause,
    @SerialName("stop") Stop,
    @SerialName("rocket") Rocket,
    @SerialName("bug") Bug,
    @SerialName("clock") Clock,
    @SerialName("calendar") Calendar,
    @SerialName("person") Person,
    @SerialName("people") People,
    @SerialName("folder") Folder,
    @SerialName("file") File,
    @SerialName("image") Image,
    @SerialName("chart") Chart,
    @SerialName("settings") Settings,
    @SerialName("lock") Lock,
    @SerialName("key") Key,
    @SerialName("cloud") Cloud,
    @SerialName("server") Server,
    @SerialName("database") Database,
}

@Serializable
enum class IconSize {
    @SerialName("sm") Sm,
    @SerialName("md") Md,
    @SerialName("lg") Lg,
    ;

    companion object {
        val default: IconSize = Md
    }
}

class CanvasParseException(message: String, cause: Throwable? = null) : Exception(message, cause)
