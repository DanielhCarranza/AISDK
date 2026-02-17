# AIDoctor v2 Migration: Exact Fixes

## Prerequisites
- Branch `feat/aisdk-v2-migration-test` created
- AISDK swapped to local path (done via `swap-to-local-aisdk.sh`)
- AISDK v2 has backward-compatibility typealiases (`V1Compatibility.swift`)

## Fix 1: Agent → LegacyAgent (3 files)

### AIChatManager.swift
Find all occurrences of `: Agent` and `Agent(` that refer to the AISDK Agent type:
```swift
// Change type declaration:
private let agent: Agent  →  private let agent: LegacyAgent

// Change initialization (~line 174):
self.agent = Agent(  →  self.agent = LegacyAgent(
```

### DocumentAnalysisService.swift
```swift
// Change type declaration (~line 12):
private let agent: Agent  →  private let agent: LegacyAgent

// Change initialization (~line 17):
self.agent = Agent(  →  self.agent = LegacyAgent(
```

### MedicationAIService.swift
```swift
// Change initialization (~line 16):
let agent = Agent(llm: openAIProvider)  →  let agent = LegacyAgent(llm: openAIProvider)
```

## Fix 2: Tool execute() return type (19 tools across ~14 files)

Every tool's `execute()` method signature and return statements need updating.

### Pattern:
```swift
// BEFORE (v1):
func execute() async throws -> (content: String, metadata: ToolMetadata?) {
    // ...
    return (content: someString, metadata: someMetadata)
}

// AFTER (v2):
func execute() async throws -> ToolResult {
    // ...
    return ToolResult(content: someString, metadata: someMetadata)
}
```

### Files to update:

**HealthTools.swift** (6 tools):
- `SearchMedicalEvidenceTool` (line ~55)
- `LogJournalEntryTool` (line ~89)
- `GeneralSearchTool` (line ~162)
- `ManageHealthEventTool` (line ~192)
- `ManageHealthReportTool` (line ~247)
- `ThinkTool` (line ~303)

**Individual tool files:**
- `DisplayMedicationTool.swift`
- `StartResearchTool.swift`
- `SearchMedicalEvidenceTool.swift` (research version)
- `ReadEvidenceTool.swift`
- `ReasonEvidenceTool.swift`
- `SearchHealthProfileTool.swift`
- `CompleteResearchTool.swift`
- `TestWearableBiomarkersTool.swift`
- `TestHealthJournalTool.swift`
- `TestLabResultsTool.swift`
- `TestMedicalHistoryTool.swift`
- `TestMedicalRecordsTool.swift`
- `TestTreatmentHistoryTool.swift`

### Sed commands (run from AIDoctor repo root):

```bash
# Fix execute() method signatures
find AIDoctor/AI -name "*.swift" -exec sed -i '' \
  's/func execute() async throws -> (content: String, metadata: ToolMetadata?)/func execute() async throws -> ToolResult/g' {} +

# Fix tuple return statements → ToolResult
# This handles: return (content: "...", metadata: ...)
find AIDoctor/AI -name "*.swift" -exec sed -i '' \
  's/return (content:/return ToolResult(content:/g' {} +
```

## Fix 3: Agent type declaration in AIChatManager

```bash
# Fix Agent → LegacyAgent in type declarations and initializations
sed -i '' 's/: Agent$/: LegacyAgent/' AIDoctor/AI/Chat/AIChatManager.swift
sed -i '' 's/= Agent(/= LegacyAgent(/' AIDoctor/AI/Chat/AIChatManager.swift
sed -i '' 's/= Agent(/= LegacyAgent(/' AIDoctor/Storage/Aggregator/DocumentAnalysisService.swift
sed -i '' 's/: Agent$/: LegacyAgent/' AIDoctor/Storage/Aggregator/DocumentAnalysisService.swift
sed -i '' 's/= Agent(/= LegacyAgent(/' AIDoctor/Care/Medication/Services/MedicationAIService.swift
```

## Verification

After applying all fixes:
```bash
xcodebuild -project AIDoctor.xcodeproj -scheme AIDoctor \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' \
  build 2>&1 | grep "error:\|BUILD"
```

Expected: `BUILD SUCCEEDED`
