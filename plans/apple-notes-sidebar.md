# Apple Notes-Style Sidebar Implementation Plan

## Overview

Redesign the ExoCortex sidebar to match the Apple Notes app pattern:
- Full vertical space utilization (edge-to-edge)
- Traffic lights in sidebar when open, in header bar when closed
- Standard macOS sidebar toggle button
- Flat list navigation without section headers
- Clean, modern appearance

## Current State

```
┌─────────────────────────────────────────────────────┐
│ [Traffic Lights]     Window Title                   │  ← Toolbar area
├────────────────┬────────────────────────────────────┤
│ Views          │                                    │
│ ├─ All         │                                    │
│ ├─ Todos       │           Editor Content           │
│ └─ ...         │                                    │
│                │                                    │
│ Settings       │                                    │
│ └─ Settings    │                                    │
└────────────────┴────────────────────────────────────┘
```

## Target State (Apple Notes Style)

### Sidebar Open
```
┌────────────────┬────────────────────────────────────┐
│[●●●] [◀]       │                                    │  ← Traffic lights + toggle in sidebar
│                │                                    │
│ All            │                                    │
│ Todos          │           Editor Content           │
│ ...            │                                    │
│                │                                    │
│ Settings       │                                    │
└────────────────┴────────────────────────────────────┘
```

### Sidebar Closed
```
┌─────────────────────────────────────────────────────┐
│ [●●●] [▶]                                           │  ← Thin header bar appears
├─────────────────────────────────────────────────────┤
│                                                     │
│                                                     │
│                   Editor Content                    │
│                                                     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Implementation Details

### 1. ExoCortexApp.swift Changes

**Current:**
```swift
.windowStyle(.hiddenTitleBar)
.windowToolbarStyle(.unifiedCompact)
```

**Target:**
```swift
.windowStyle(.hiddenTitleBar)
.windowToolbarStyle(.unified) // or use .automatic for better integration
```

Key changes:
- Window style already uses `.hiddenTitleBar` which is correct
- May need to adjust toolbar style for proper traffic light positioning

### 2. ContentView.swift - SidebarView Changes

**Current SidebarView:**
```swift
List(selection: $selection) {
    Section("Views") {
        ForEach(viewsManager.views) { view in
            NavigationLink(value: SidebarSelection.view(view)) {
                Label(view.name, systemImage: view.icon)
            }
        }
    }
    
    Section {
        NavigationLink(value: SidebarSelection.settings) {
            Label("Settings", systemImage: "gear")
        }
    }
}
.listStyle(.sidebar)
```

**Target SidebarView (flat list with subtle divider):**
```swift
List(selection: $selection) {
    // Views as flat list - no section header
    ForEach(viewsManager.views) { view in
        NavigationLink(value: SidebarSelection.view(view)) {
            Label(view.name, systemImage: view.icon)
        }
    }
    
    // Subtle divider between views and settings
    Divider()
        .padding(.vertical, 4)
    
    // Settings at bottom - no section header
    NavigationLink(value: SidebarSelection.settings) {
        Label("Settings", systemImage: "gear")
    }
}
.listStyle(.sidebar)
```

**Note:** The `Divider()` in a List with `.sidebar` style will render as a subtle horizontal line, providing visual separation without the heavy section header styling.

### 3. Traffic Light and Header Bar Logic

**macOS-specific implementation:**

The key is using `NavigationSplitView` with proper toolbar configuration:

```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    SidebarView(...)
        .toolbar(removing: .sidebarToggle) // We'll handle toggle ourselves if needed
        .toolbar {
            // Toolbar content appears in sidebar header when visible
            ToolbarItem(placement: .automatic) {
                // Toggle button if needed
            }
        }
} detail: {
    detailContent
        .toolbar {
            // When sidebar is hidden, toggle appears here
            ToolbarItem(placement: .navigation) {
                if columnVisibility == .detailOnly {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.left")
                    }
                }
            }
        }
}
```

Alternative: Use `safeAreaInset` for the header bar:

```swift
// Detail view with conditional header
detailContent
    .safeAreaInset(edge: .top) {
        if columnVisibility == .detailOnly {
            HStack {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.left")
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
```

### 4. Full Height Sidebar

To achieve full height:
- Use `.toolbar(removing: .title)` on detail view
- Avoid adding extra toolbar items that create title bar space
- Use `.navigationSplitViewStyle(.balanced)` or `.prominentDetail` as needed

### 5. Clean Up Styling

Remove any special formatting:
- No decorative elements
- Standard system fonts
- Standard selection highlighting
- Minimal visual hierarchy

## Files to Modify

1. **ExoCortexApp.swift**
   - Verify window style configuration
   - Keep `SidebarCommands()` for keyboard shortcut support

2. **ContentView.swift**
   - Rewrite `SidebarView` to use flat list
   - Add header bar logic for closed state
   - Handle sidebar toggle visibility
   - Clean up any decorative styling

## Technical Considerations

1. **NavigationSplitView columnVisibility binding**
   - Use `@State private var columnVisibility: NavigationSplitViewVisibility`
   - Check `.detailOnly` vs `.all` for conditional rendering

2. **Traffic lights behavior**
   - macOS handles this automatically with proper window/toolbar configuration
   - `.hiddenTitleBar` window style should allow traffic lights in sidebar area

3. **Sidebar toggle**
   - `SidebarCommands()` provides Cmd+Ctrl+S shortcut
   - For visual toggle, use standard `Toggle` or `Button` with sidebar.left icon

4. **Testing**
   - Test sidebar open/close transitions
   - Verify traffic lights move correctly
   - Ensure editor fills available space
   - Check keyboard navigation works
