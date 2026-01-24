# fn-1.43 Task 5.5: Core 8 SwiftUI Views

## Description
Implement SwiftUI view components for the Core 8 UI component definitions, enabling the json-render pattern to translate UITree nodes into native SwiftUI views.

## Acceptance
- [x] GenerativeTextView - Renders text with style support (body, headline, subheadline, caption, title)
- [x] GenerativeButtonView - Interactive button with action handling and style variants (primary, secondary, destructive, plain)
- [x] GenerativeCardView - Container with optional title/subtitle and child rendering
- [x] GenerativeInputView - Text input field with label and placeholder
- [x] GenerativeListView - Ordered/unordered/plain list container with child items
- [x] GenerativeImageView - Async image loading with content mode support and invalid URL handling
- [x] GenerativeStackView - HStack/VStack layout with spacing and alignment
- [x] GenerativeSpacerView - Flexible or fixed-size spacing element with accessibility hiding
- [x] All views implement comprehensive accessibility support (label, hint, traits)
- [x] AccessibilityTraits mapping from string to SwiftUI traits (header, link, button, image, staticText, selected, summary)
- [x] Views decode props from UINode.propsData using JSONDecoder
- [x] Container views use ChildViewBuilder closure for child rendering
- [x] Stable ForEach IDs using node.key instead of offset
- [x] Action name normalization (trim whitespace) for security
- [x] secureDefault registry with pre-configured action allowlist
- [x] Invalid/empty URL handled gracefully in ImageView
- [x] Default registry (UIComponentRegistry.default) includes all Core 8 views
- [x] All tests pass (swift test --filter UIComponentRegistryTests)

## Done summary
All 8 Core SwiftUI view components implemented in UIComponentRegistry.swift with comprehensive fixes:
- Text, Button, Card, Input, List, Image, Stack, Spacer
- Full accessibility support including trait mapping (header, link, button, image, staticText, selected, summary)
- Stable ForEach IDs using node.key for proper SwiftUI state management
- Action normalization (trim whitespace) for consistent security checks
- secureDefault registry with pre-configured allowlist (submit, navigate, dismiss)
- Invalid/empty URL gracefully shows placeholder in ImageView
- Fixed-size spacer uses Color.clear for predictable sizing
- Image fill mode clips when frame is set
- Plain list style omits marker spacing
- 23 tests pass covering registration, action handling, and view building

## Evidence
- Commits: (pending)
- Tests: swift test --filter UIComponentRegistryTests (23 tests pass)
- PRs:
