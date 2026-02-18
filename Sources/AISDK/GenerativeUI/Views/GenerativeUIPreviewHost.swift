//
//  GenerativeUIPreviewHost.swift
//  AISDK
//
//  SwiftUI preview host for Generative UI components
//

#if DEBUG && canImport(SwiftUI)
import SwiftUI

private enum GenerativeUIPreviewData {
    static let json = """
    {
      "root": "preview",
      "elements": {
        "preview": {
          "type": "Stack",
          "props": { "direction": "vertical", "spacing": 12 },
          "children": ["metric", "badge", "bar", "controls", "tabs"]
        },
        "metric": { "type": "Metric", "props": { "label": "Revenue", "value": 125000, "format": "currency", "trend": "up", "change": 12.5 } },
        "badge": { "type": "Badge", "props": { "text": "On Track", "variant": "success" } },
        "bar": { "type": "BarChart", "props": { "data": [ { "label": "Jan", "value": 100 }, { "label": "Feb", "value": 150 } ], "showValues": true } },
        "controls": {
          "type": "Stack",
          "props": { "direction": "vertical", "spacing": 8 },
          "children": ["toggle", "slider"]
        },
        "toggle": { "type": "Toggle", "props": { "label": "Enable", "name": "enable", "value": true } },
        "slider": { "type": "Slider", "props": { "label": "Volume", "name": "volume", "min": 0, "max": 100, "value": 30, "showValue": true } },
        "tabs": {
          "type": "Tabs",
          "props": { "tabs": [ { "key": "overview", "label": "Overview" }, { "key": "details", "label": "Details" } ], "selected": "overview" },
          "children": ["overview", "details"]
        },
        "overview": { "type": "Text", "props": { "content": "Overview content" } },
        "details": { "type": "Text", "props": { "content": "Details content" } }
      }
    }
    """
}

struct GenerativeUIPreviewHost: View {
    private let tree: UITree?

    init() {
        if let data = GenerativeUIPreviewData.json.data(using: .utf8) {
            tree = try? UITree.parse(from: data, validatingWith: UICatalog.extended)
        } else {
            tree = nil
        }
    }

    var body: some View {
        if let tree {
            ScrollView {
                GenerativeUIView(tree: tree, registry: .extended, onAction: { _ in })
                    .padding()
            }
        } else {
            Text("Preview data failed to load")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Generative UI") {
    GenerativeUIPreviewHost()
}
#endif
