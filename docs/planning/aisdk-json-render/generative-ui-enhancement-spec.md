# Generative UI Enhancement Specification

This specification outlines enhancements to the AISDK json-render implementation to enable richer, iOS-ready UI generation including data visualization, advanced layouts, and interactive components.

## Executive Summary

**Goal:** Enhance the current Core 8 component catalog to support data visualization (charts, graphs, metrics), advanced layouts (grids, tabs, sections), and additional interactive components while maintaining the existing architecture's simplicity and security model.

**Approach:** Incremental enhancement—add new components to the existing `UICatalog` and `UIComponentRegistry` systems without architectural overhaul.

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Proposed Enhancements](#proposed-enhancements)
3. [New Component Catalog](#new-component-catalog)
4. [Implementation Details](#implementation-details)
5. [File Changes](#file-changes)
6. [Testing Strategy](#testing-strategy)
7. [Sources and References](#sources-and-references)

---

## Current State Analysis

### Existing Components (Core 8)

| Component | Props | Purpose |
|-----------|-------|---------|
| Text | content, style | Display text content |
| Button | title, action, style, disabled | Interactive actions |
| Card | title, subtitle, style | Container with header |
| Input | label, name, placeholder, type, validation | Form input |
| List | style (ordered/unordered/plain) | List container |
| Image | url, alt, width, height, contentMode | Display images |
| Stack | direction, spacing, alignment | Layout container |
| Spacer | size | Flexible spacing |

### Architecture Strengths (Preserve)

- **UICatalog** system for prompt generation and validation
- **UIComponentRegistry** for SwiftUI rendering with action allowlist
- **UITree** parsing with security limits (depth: 100, nodes: 10,000)
- **60fps throttled** update batching in ViewModel
- **Action allowlist** security model

### Known Gaps (Address)

1. No data visualization components (charts, graphs, metrics)
2. No grid layout system
3. No toggle, slider, or picker components
4. No progress/loading indicators
5. No badge/tag components for status display
6. No divider/separator components
7. No section headers for grouping

---

## Proposed Enhancements

### Enhancement Tiers

#### Tier 1: Essential (High Impact, Low Complexity)
Components that immediately elevate UI quality with minimal implementation effort.

- **Metric** - Display key values with labels and formatting
- **Badge** - Status indicators and tags
- **Divider** - Visual separators
- **Section** - Grouped content with headers
- **Progress** - Progress bars and indicators

#### Tier 2: Data Visualization (High Impact, Medium Complexity)
Charts and graphs for data-driven UIs.

- **BarChart** - Horizontal/vertical bar charts
- **LineChart** - Trend lines and time series
- **PieChart** - Distribution visualization
- **Gauge** - Circular progress/value indicators

#### Tier 3: Interactive (Medium Impact, Medium Complexity)
Enhanced user input components.

- **Toggle** - Boolean switches
- **Slider** - Range input
- **Stepper** - Increment/decrement numeric values
- **SegmentedControl** - Option selection
- **Picker** - Selection from options

#### Tier 4: Layout (Medium Impact, Low Complexity)
Advanced layout components.

- **Grid** - Multi-column layouts
- **Tabs** - Tabbed content views
- **Accordion** - Collapsible sections

---

## New Component Catalog

### Tier 1 Components

#### Metric
Display formatted values with labels—perfect for dashboards.

```json
{
  "type": "Metric",
  "props": {
    "label": "Revenue",
    "value": 125000,
    "format": "currency",
    "trend": "up",
    "change": 12.5
  }
}
```

**Props:**
- `label: String` (required) - Metric label
- `value: Double` (required) - Numeric value
- `format: String` (optional) - "number" | "currency" | "percent" | "compact"
- `trend: String` (optional) - "up" | "down" | "neutral"
- `change: Double` (optional) - Change value/percentage
- `prefix: String` (optional) - Value prefix (e.g., "$")
- `suffix: String` (optional) - Value suffix (e.g., "%")

**SwiftUI Implementation:** Custom view with SF Symbols for trend arrows, NumberFormatter for formatting.

---

#### Badge
Status indicators and tags.

```json
{
  "type": "Badge",
  "props": {
    "text": "Active",
    "variant": "success"
  }
}
```

**Props:**
- `text: String` (required) - Badge text
- `variant: String` (optional) - "default" | "success" | "warning" | "error" | "info"
- `size: String` (optional) - "small" | "medium" | "large"

**SwiftUI Implementation:** Capsule-shaped view with semantic colors.

---

#### Divider
Visual separators.

```json
{
  "type": "Divider",
  "props": {
    "label": "OR"
  }
}
```

**Props:**
- `label: String` (optional) - Center text
- `style: String` (optional) - "solid" | "dashed"

**SwiftUI Implementation:** Native `Divider()` or custom with optional label.

---

#### Section
Grouped content with headers.

```json
{
  "type": "Section",
  "props": {
    "title": "Account Settings",
    "subtitle": "Manage your preferences"
  },
  "children": ["setting1", "setting2"]
}
```

**Props:**
- `title: String` (optional) - Section header
- `subtitle: String` (optional) - Section description
- `collapsible: Bool` (optional) - Allow collapse/expand

**SwiftUI Implementation:** VStack with header styling, optional disclosure.

---

#### Progress
Progress indicators.

```json
{
  "type": "Progress",
  "props": {
    "value": 0.75,
    "label": "Upload Progress",
    "showValue": true
  }
}
```

**Props:**
- `value: Double` (optional) - Progress 0.0-1.0 (nil = indeterminate)
- `label: String` (optional) - Progress label
- `showValue: Bool` (optional) - Show percentage text
- `style: String` (optional) - "linear" | "circular"
- `color: String` (optional) - "accent" | "success" | "warning" | "error"

**SwiftUI Implementation:** Native `ProgressView` with styling.

---

### Tier 2 Components (Data Visualization)

#### BarChart
Bar chart visualization.

```json
{
  "type": "BarChart",
  "props": {
    "data": [
      {"label": "Jan", "value": 100},
      {"label": "Feb", "value": 150},
      {"label": "Mar", "value": 120}
    ],
    "orientation": "vertical",
    "showLabels": true
  }
}
```

**Props:**
- `data: [ChartDataPoint]` (required) - Array of {label, value, color?}
- `orientation: String` (optional) - "vertical" | "horizontal"
- `showLabels: Bool` (optional) - Show axis labels
- `showValues: Bool` (optional) - Show value labels on bars
- `barColor: String` (optional) - Default bar color
- `height: Double` (optional) - Chart height

**SwiftUI Implementation:** Swift Charts `BarMark` or custom drawing.

---

#### LineChart
Line chart for trends.

```json
{
  "type": "LineChart",
  "props": {
    "series": [
      {
        "name": "Revenue",
        "data": [
          {"x": "Jan", "y": 100},
          {"x": "Feb", "y": 150}
        ]
      }
    ],
    "showPoints": true,
    "smooth": true
  }
}
```

**Props:**
- `series: [ChartSeries]` (required) - Array of named data series
- `showPoints: Bool` (optional) - Show data points
- `smooth: Bool` (optional) - Smooth line interpolation
- `showGrid: Bool` (optional) - Show background grid
- `height: Double` (optional) - Chart height

**SwiftUI Implementation:** Swift Charts `LineMark` with optional `PointMark`.

---

#### PieChart
Pie/donut chart for distributions.

```json
{
  "type": "PieChart",
  "props": {
    "data": [
      {"label": "Desktop", "value": 60, "color": "#007AFF"},
      {"label": "Mobile", "value": 30, "color": "#34C759"},
      {"label": "Tablet", "value": 10, "color": "#FF9500"}
    ],
    "donut": true,
    "showLegend": true
  }
}
```

**Props:**
- `data: [PieSlice]` (required) - Array of {label, value, color?}
- `donut: Bool` (optional) - Render as donut chart
- `showLegend: Bool` (optional) - Show legend
- `showLabels: Bool` (optional) - Show slice labels

**SwiftUI Implementation:** Swift Charts `SectorMark` or custom arc drawing.

---

#### Gauge
Circular gauge/progress ring.

```json
{
  "type": "Gauge",
  "props": {
    "value": 0.72,
    "label": "CPU Usage",
    "min": 0,
    "max": 100
  }
}
```

**Props:**
- `value: Double` (required) - Current value
- `label: String` (optional) - Center label
- `min: Double` (optional) - Minimum value (default 0)
- `max: Double` (optional) - Maximum value (default 1)
- `showValue: Bool` (optional) - Show numeric value
- `color: String` (optional) - Gauge color

**SwiftUI Implementation:** Native `Gauge` view or custom circular progress.

---

### Tier 3 Components (Interactive)

#### Toggle
Boolean switch.

```json
{
  "type": "Toggle",
  "props": {
    "label": "Enable Notifications",
    "name": "notifications",
    "value": true
  }
}
```

**Props:**
- `label: String` (required) - Toggle label
- `name: String` (required) - Form field name
- `value: Bool` (optional) - Initial value
- `disabled: Bool` (optional) - Disabled state

**SwiftUI Implementation:** Native `Toggle` view.

---

#### Slider
Range input.

```json
{
  "type": "Slider",
  "props": {
    "label": "Volume",
    "name": "volume",
    "min": 0,
    "max": 100,
    "value": 50,
    "step": 1
  }
}
```

**Props:**
- `label: String` (required) - Slider label
- `name: String` (required) - Form field name
- `min: Double` (required) - Minimum value
- `max: Double` (required) - Maximum value
- `value: Double` (optional) - Initial value
- `step: Double` (optional) - Step increment
- `showValue: Bool` (optional) - Show current value

**SwiftUI Implementation:** Native `Slider` view.

---

#### SegmentedControl
Option selection.

```json
{
  "type": "SegmentedControl",
  "props": {
    "name": "view_mode",
    "options": [
      {"value": "list", "label": "List"},
      {"value": "grid", "label": "Grid"}
    ],
    "selected": "list"
  }
}
```

**Props:**
- `name: String` (required) - Form field name
- `options: [Option]` (required) - Array of {value, label, icon?}
- `selected: String` (optional) - Initially selected value

**SwiftUI Implementation:** Native `Picker` with `.segmented` style.

---

### Tier 4 Components (Layout)

#### Grid
Multi-column grid layout.

```json
{
  "type": "Grid",
  "props": {
    "columns": 2,
    "spacing": 16
  },
  "children": ["card1", "card2", "card3", "card4"]
}
```

**Props:**
- `columns: Int` (required) - Number of columns
- `spacing: Double` (optional) - Grid spacing
- `alignment: String` (optional) - "leading" | "center" | "trailing"

**SwiftUI Implementation:** `LazyVGrid` with `GridItem`.

---

#### Tabs
Tabbed content container.

```json
{
  "type": "Tabs",
  "props": {
    "tabs": [
      {"key": "overview", "label": "Overview"},
      {"key": "details", "label": "Details"}
    ],
    "selected": "overview"
  },
  "children": ["overview_content", "details_content"]
}
```

**Props:**
- `tabs: [Tab]` (required) - Array of {key, label, icon?}
- `selected: String` (optional) - Initially selected tab key

**SwiftUI Implementation:** Custom tab bar with content switching.

---

## Implementation Details

### File Changes

#### New Files to Create

```
Sources/AISDK/GenerativeUI/Catalog/
├── Tier1Components.swift       # Metric, Badge, Divider, Section, Progress
├── ChartComponents.swift       # BarChart, LineChart, PieChart, Gauge
├── InteractiveComponents.swift # Toggle, Slider, SegmentedControl
└── LayoutComponents.swift      # Grid, Tabs
```

#### Files to Modify

| File | Changes |
|------|---------|
| `UICatalog.swift` | Add new component registrations, create `extended` catalog |
| `UIComponentRegistry.swift` | Add SwiftUI view builders for new components |
| `Core8Components.swift` | (No changes - preserve backward compatibility) |
| `TerminalUIRenderer.swift` | Add ASCII renderers for new components |

### Catalog Organization

```swift
// UICatalog.swift additions

extension UICatalog {
    /// Core 8 components (existing)
    public static let core8 = UICatalog(...)

    /// Extended catalog with data visualization
    public static let extended: UICatalog = {
        var catalog = core8
        catalog.registerComponents(Tier1Components.all)
        catalog.registerComponents(ChartComponents.all)
        catalog.registerComponents(InteractiveComponents.all)
        catalog.registerComponents(LayoutComponents.all)
        return catalog
    }()

    /// Dashboard-focused catalog
    public static let dashboard: UICatalog = {
        var catalog = core8
        catalog.registerComponents(Tier1Components.all)
        catalog.registerComponents(ChartComponents.all)
        return catalog
    }()
}
```

### Props Type Definitions

```swift
// Tier1Components.swift

struct MetricProps: Codable {
    let label: String
    let value: Double
    var format: MetricFormat?
    var trend: Trend?
    var change: Double?
    var prefix: String?
    var suffix: String?

    enum MetricFormat: String, Codable {
        case number, currency, percent, compact
    }

    enum Trend: String, Codable {
        case up, down, neutral
    }
}

struct BadgeProps: Codable {
    let text: String
    var variant: BadgeVariant?
    var size: BadgeSize?

    enum BadgeVariant: String, Codable {
        case `default`, success, warning, error, info
    }

    enum BadgeSize: String, Codable {
        case small, medium, large
    }
}
```

### Chart Data Models

```swift
// ChartComponents.swift

struct ChartDataPoint: Codable {
    let label: String
    let value: Double
    var color: String?
}

struct ChartSeries: Codable {
    let name: String
    let data: [SeriesPoint]
    var color: String?

    struct SeriesPoint: Codable {
        let x: String
        let y: Double
    }
}

struct PieSlice: Codable {
    let label: String
    let value: Double
    var color: String?
}
```

### SwiftUI View Examples

```swift
// MetricView.swift

struct MetricView: View {
    let props: MetricProps

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(props.label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formattedValue)
                    .font(.title.bold())

                if let trend = props.trend, let change = props.change {
                    TrendIndicator(trend: trend, change: change)
                }
            }
        }
    }

    private var formattedValue: String {
        // Format based on props.format
    }
}

struct TrendIndicator: View {
    let trend: MetricProps.Trend
    let change: Double

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: trend == .up ? "arrow.up" : "arrow.down")
            Text("\(abs(change), specifier: "%.1f")%")
        }
        .font(.caption.bold())
        .foregroundStyle(trend == .up ? .green : .red)
    }
}
```

### Registry Registration

```swift
// UIComponentRegistry+Extended.swift

extension UIComponentRegistry {
    public static let extended: UIComponentRegistry = {
        var registry = UIComponentRegistry.default

        // Tier 1
        registry.register("Metric") { node, tree, decoder, actionHandler, childBuilder in
            let props = try decoder.decode(MetricProps.self, from: node.propsData)
            return AnyView(MetricView(props: props))
        }

        registry.register("Badge") { node, tree, decoder, actionHandler, childBuilder in
            let props = try decoder.decode(BadgeProps.self, from: node.propsData)
            return AnyView(BadgeView(props: props))
        }

        // ... additional registrations

        return registry
    }()
}
```

---

## Testing Strategy

### Unit Tests

1. **Props Decoding Tests**
   - Test each new component's props decode correctly
   - Test optional fields default properly
   - Test validation errors for invalid props

2. **Catalog Validation Tests**
   - Test component types are recognized
   - Test props validation catches invalid data
   - Test children constraints are enforced

3. **Rendering Tests**
   - Snapshot tests for each new SwiftUI component
   - Test different prop combinations render correctly

### Integration Tests

1. **Full Pipeline Test**
   - Generate prompt with extended catalog
   - Parse sample JSON with new components
   - Validate tree structure
   - Render to SwiftUI

2. **CLI Renderer Tests**
   - Test terminal output for new components
   - Verify graceful fallback for unsupported features

### Test Files to Create

```
Tests/AISDKTests/GenerativeUI/
├── Tier1ComponentTests.swift
├── ChartComponentTests.swift
├── InteractiveComponentTests.swift
├── LayoutComponentTests.swift
└── ExtendedCatalogTests.swift
```

---

## Verification Steps

1. **Build and run tests:**
   ```bash
   swift test --filter GenerativeUI
   ```

2. **Test with CLI:**
   ```bash
   swift run AISDKCLI --format ui "Show me a dashboard with revenue metrics"
   ```

3. **Test SwiftUI rendering:**
   - Create sample JSON with new components
   - Render with `GenerativeUIView` using `UIComponentRegistry.extended`
   - Verify visual output matches expectations

4. **Verify prompt generation:**
   ```swift
   let prompt = UICatalog.extended.generatePrompt()
   // Verify new components are documented in prompt
   ```

---

## Implementation Priority

### Phase 1: Tier 1 Essential (Week 1)
- Metric, Badge, Divider, Section, Progress
- Immediate visual improvement with low complexity

### Phase 2: Charts (Week 2)
- BarChart, LineChart, PieChart, Gauge
- Requires Swift Charts integration

### Phase 3: Interactive (Week 3)
- Toggle, Slider, SegmentedControl
- Form state considerations

### Phase 4: Layout (Week 4)
- Grid, Tabs
- Container component patterns

---

## Sources and References

### Primary References

1. **Current Implementation Documentation**
   - `docs/json-render-implementation.md` - Current AISDK implementation details

2. **Vercel json-render Reference**
   - `docs/planning/aisdk-json-render/reference-implementations/json-render.md`
   - `docs/planning/aisdk-json-render/reference-implementations/json-render-catalog.md`
   - `docs/planning/aisdk-json-render/reference-implementations/json-render-react.md`
   - `docs/planning/aisdk-json-render/reference-implementations/json-render-streaming.md`

3. **json-render.dev**
   - https://json-render.dev/ - Official site
   - https://json-render.dev/docs - Documentation
   - https://json-render.dev/playground - Live playground
   - GitHub: https://github.com/vercel-labs/json-render

### SwiftUI Implementation References

4. **Swift Charts**
   - Apple Documentation: https://developer.apple.com/documentation/charts
   - Use for BarChart, LineChart, PieChart components

5. **SwiftUI Components**
   - `Toggle`, `Slider`, `Picker`, `Gauge` - Native SwiftUI
   - `LazyVGrid` - For Grid component

### Key Files in Codebase

```
Sources/AISDK/GenerativeUI/
├── Models/UITree.swift                    # Tree parsing and validation
├── Catalog/UICatalog.swift                # Component catalog system
├── Catalog/Core8Components.swift          # Existing component definitions
├── Registry/UIComponentRegistry.swift     # SwiftUI view registration
├── Views/GenerativeUIView.swift           # Main rendering view
└── ViewModels/GenerativeUIViewModel.swift # State management

Examples/AISDKCLI/
├── CLIController.swift                    # CLI integration
└── Renderers/TerminalUIRenderer.swift     # ASCII rendering
```

---

## Out of Scope (Future Consideration)

The following features are intentionally excluded from this spec to maintain focus:

1. **JSONL Streaming/Patching** - Would require significant architectural changes
2. **Data Binding ($data references)** - Complex state management implications
3. **Visibility Rules ($auth)** - Requires auth context integration
4. **Form State Management** - Input binding to form submission
5. **Animations/Transitions** - Can be added per-component later

These may be addressed in future enhancement phases.
