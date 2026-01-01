# Hierarchical Sidebar Implementation Plan

## Overview

Implement Apple Mail-style hierarchical sidebar with collapsible groups based on view icons.

## Design

### Icon-to-Category Mapping

Views are automatically grouped based on their SF Symbol icons:

| Category | Icons | Example Views |
|----------|-------|---------------|
| Library | `book.pages`, `doc.text`, `sparkles` | Worklog, AI Responses |
| Tasks | `checklist`, `checkmark.circle` | Open Todos, Completed |
| People | `person`, `person.fill`, `person.2` | Personal |
| Tags | `briefcase`, `tag` | Work |
| Other | Any unmapped icon | Custom views |

### Visual Structure

```
▼ Library
    📖 Worklog
    ✨ AI Responses
▼ Tasks  
    ☑️ Open Todos
    ✅ Completed
▼ Tags
    💼 Work
▼ People
    👤 Personal
──────────────
⚙️ Settings
```

## Implementation

### File: NamedView.swift

Add a new `SidebarCategory` enum:

```swift
// MARK: - Sidebar Category

/// Categories for grouping sidebar items
enum SidebarCategory: String, CaseIterable, Identifiable {
    case library = "Library"
    case tasks = "Tasks"
    case tags = "Tags"
    case people = "People"
    case other = "Other"
    
    var id: String { rawValue }
    
    /// Icon for the category header
    var icon: String {
        switch self {
        case .library: return "books.vertical"
        case .tasks: return "checklist"
        case .tags: return "tag"
        case .people: return "person.2"
        case .other: return "square.grid.2x2"
        }
    }
    
    /// Maps SF Symbol icon names to categories
    static func category(for icon: String) -> SidebarCategory {
        switch icon {
        case "book.pages", "doc.text", "sparkles", "doc.richtext":
            return .library
        case "checklist", "checkmark.circle", "checklist.unchecked", 
             "checkmark.circle.fill", "square", "checkmark.square":
            return .tasks
        case "person", "person.fill", "person.2", "person.2.fill":
            return .people
        case "briefcase", "briefcase.fill", "tag", "tag.fill", "number":
            return .tags
        default:
            return .other
        }
    }
}
```

Add a convenience computed property to `NamedView`:

```swift
extension NamedView {
    /// The category this view belongs to based on its icon
    var category: SidebarCategory {
        SidebarCategory.category(for: icon)
    }
}
```

### File: ContentView.swift

Update `SidebarView`:

```swift
struct SidebarView: View {
    @ObservedObject var viewsManager: ViewsManager
    @EnvironmentObject var viewModel: LogViewModel
    @Binding var selection: SidebarSelection?
    
    /// Tracks expansion state for each category
    @State private var expandedCategories: Set<SidebarCategory> = Set(SidebarCategory.allCases)
    
    /// Groups views by category
    private var groupedViews: [SidebarCategory: [NamedView]] {
        Dictionary(grouping: viewsManager.views) { $0.category }
    }
    
    /// Categories that have at least one view, in display order
    private var activeCategories: [SidebarCategory] {
        SidebarCategory.allCases.filter { groupedViews[$0]?.isEmpty == false }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(activeCategories) { category in
                    Section(isExpanded: Binding(
                        get: { expandedCategories.contains(category) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedCategories.insert(category)
                            } else {
                                expandedCategories.remove(category)
                            }
                        }
                    )) {
                        ForEach(groupedViews[category] ?? []) { view in
                            NavigationLink(value: SidebarSelection.view(view)) {
                                Label(view.name, systemImage: view.icon)
                            }
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            // Settings button at bottom
            Button {
                selection = .settings
            } label: {
                HStack {
                    Label("Settings", systemImage: "gear")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(selection == .settings ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .navigationTitle("ExoCortex")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        #endif
    }
}
```

## Why This Is Clean

1. **No Model Changes Required** - The category is derived from the existing `icon` property
2. **Single Source of Truth** - Icon-to-category mapping lives in one place
3. **Extensible** - Easy to add new categories or change icon mappings
4. **Backward Compatible** - Existing views work without modification
5. **Apple-Native** - Uses SwiftUI's built-in `Section(isExpanded:)` for disclosure

## Considerations

### UserDefaults Persistence for Expansion State

Optionally persist `expandedCategories` to remember user preferences:

```swift
@AppStorage("sidebarExpandedCategories") 
private var expandedCategoriesData: Data = Data()

// Load/save using Codable
```

### Future Enhancement: Custom Categories

If users want more control, the model could be extended later to support explicit categories:

```swift
struct NamedView {
    // ...existing properties...
    var customCategory: String?  // Optional override
    
    var category: SidebarCategory {
        if let custom = customCategory {
            return SidebarCategory(rawValue: custom) ?? .other
        }
        return SidebarCategory.category(for: icon)
    }
}
```

## Testing

1. Verify grouping works with example views
2. Test collapsing/expanding sections
3. Verify selection works across categories
4. Test with empty categories (should be hidden)
5. Test adding new views dynamically
