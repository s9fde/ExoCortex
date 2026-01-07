# Simplify to Standard macOS Sidebar

## Goal

Remove all custom Apple Notes-style complexity and return to a plain vanilla SwiftUI sidebar implementation using `NavigationSplitView`.

## Current Complexity to Remove

### ContentView.swift - Lines to Remove/Replace

1. **Custom `appleNotesLayout`** (lines 69-107) - Replace with standard `NavigationSplitView`
2. **`sidebarHeader`** (lines 110-123) - Remove entirely
3. **`collapsedHeader`** (lines 126-140) - Remove entirely
4. **`showSidebar` state** (line 27) - Remove, let system handle
5. **Custom HStack/VStack layout** - Use `NavigationSplitView` instead

### ExoCortexApp.swift - Lines to Simplify

1. **`.windowStyle(.hiddenTitleBar)`** (line 47) - Remove to restore standard title bar
2. **`.windowToolbarStyle(.unifiedCompact)`** (line 48) - Change to `.automatic` or remove

### SidebarView - Keep Simple

The current flat list with `Divider()` is fine, but optionally could use standard sections:
- Add `Section` headers back for Views and Settings
- Or keep flat list - either approach is standard

## Target Architecture

```
┌─────────────────────────────────────────────────────┐
│ [●●●]           ExoCortex           [Sidebar Toggle]│  ← Standard title bar
├────────────────┬────────────────────────────────────┤
│                │                                    │
│ All            │                                    │
│ Todos          │           Editor Content           │
│ ...            │                                    │
│ ────────       │                                    │
│ Settings       │                                    │
└────────────────┴────────────────────────────────────┘
```

## Simplified Code Structure

### ContentView.swift - mainContent

```swift
private var mainContent: some View {
    NavigationSplitView {
        SidebarView(viewsManager: viewsManager, selection: $sidebarSelection)
            .environment(viewModel)
    } detail: {
        detailContent
    }
    .onChange(of: sidebarSelection) { _, newSelection in
        if case .view(let view) = newSelection {
            viewsManager.selectView(view)
        }
    }
}
```

No more:
- Platform-specific `#if os(macOS)` for layout
- Custom HSplitView
- Manual sidebar toggle
- Custom headers

### ExoCortexApp.swift - Window Configuration

```swift
WindowGroup {
    ContentView()
        .environment(viewModel)
        // ... existing lifecycle handlers
}
.commands {
    SidebarCommands() // Standard sidebar toggle via Cmd+Ctrl+S
    // ... existing commands
}
```

No more:
- `.windowStyle(.hiddenTitleBar)`
- `.windowToolbarStyle(.unifiedCompact)`

## Files to Modify

| File | Changes |
|------|---------|
| `ContentView.swift` | Remove custom macOS layout, use NavigationSplitView everywhere |
| `ExoCortexApp.swift` | Remove hidden title bar styling, add SidebarCommands |

## What Stays the Same

- `LockScreen` - No changes
- `LogEditorView` - No changes to the editor itself
- `SidebarSelection` enum - Keep as is
- All view model logic - Unchanged
- Widget/view appearance - Unchanged

## Benefits

1. **Standard macOS behavior** - Traffic lights, title bar, sidebar toggle all work as expected
2. **Less code to maintain** - Remove ~70 lines of custom layout code
3. **System consistency** - App looks and behaves like other native macOS apps
4. **Future-proof** - Apple may change sidebar APIs; standard implementation will adapt
