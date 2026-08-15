import WidgetKit
import SwiftUI

/// WidgetBundleBuilder allows at most 10 children — nest for twelve kinds.
@main
struct AgentCanvasBundle: WidgetBundle {
    var body: some Widget {
        FirstTenCanvasWidgets()
        ExtraCanvasWidgets()
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
