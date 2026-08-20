import WidgetKit
import SwiftUI

/// WidgetBundleBuilder allows at most 10 children — nest for twelve kinds.
@main
struct AgentCanvasBundle: WidgetBundle {
    var body: some Widget {
        // Nested types are WidgetBundle, not Widget. Use their `body`
        // (opaque Widget) so the builder stays under the 10-child limit.
        FirstTenCanvasWidgets().body
        ExtraCanvasWidgets().body
    }
}

struct FirstTenCanvasWidgets: WidgetBundle {
    var body: some Widget {
        OneWidget()
        TwoWidget()
        ThreeWidget()
        FourWidget()
        FiveWidget()
        SixWidget()
        SevenWidget()
        EightWidget()
        NineWidget()
        TenWidget()
    }
}

struct ExtraCanvasWidgets: WidgetBundle {
    var body: some Widget {
        ElevenWidget()
        TwelveWidget()
    }
}
