//
//  NamedView.swift
//  ExoCortex
//
//  Model for user-defined filter views.
//

import Foundation
import SwiftUI

// MARK: - Named View Model

/// Represents a saved filter view that users can create and manage.
/// Views filter the log content based on a query string.
struct NamedView: Identifiable, Codable, Equatable, Hashable {
    /// Unique identifier
    let id: UUID
    
    /// Display name shown in sidebar
    var name: String
    
    /// Filter query string (e.g., "todo:open", "#work", "http")
    var filter: String
    
    /// SF Symbol icon name (optional)
    var icon: String
    
    /// Whether this is the built-in "All" view (cannot be deleted)
    var isBuiltIn: Bool
    
    // MARK: - Initialization
    
    init(id: UUID = UUID(), name: String, filter: String, icon: String = "doc.text", isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.filter = filter
        self.icon = icon
        self.isBuiltIn = isBuiltIn
    }
    
    // MARK: - Built-in Views
    
    /// The default "All" view showing all content
    static let all = NamedView(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        name: "Worklog",
        filter: "",
        icon: "book.pages",
        isBuiltIn: true
    )
    
    // MARK: - Example Views
    
    /// Example views for demonstration
    static let examples: [NamedView] = [
        NamedView(name: "Open Todos", filter: "todo:open", icon: "checklist"),
        NamedView(name: "Completed", filter: "todo:done", icon: "checkmark.circle"),
        NamedView(name: "AI Responses", filter: LLMConfig.responseTag, icon: "sparkles"),
        NamedView(name: "Work", filter: "#work", icon: "briefcase"),
        NamedView(name: "Personal", filter: "#personal", icon: "person"),
    ]
}

// MARK: - Sidebar Category

/// Categories for grouping sidebar items by icon
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

// MARK: - NamedView Extensions

extension NamedView {
    /// The category this view belongs to based on its icon
    var category: SidebarCategory {
        SidebarCategory.category(for: icon)
    }
}

// MARK: - Views Manager

/// Manages the collection of named views, persisting to UserDefaults.
@MainActor
final class ViewsManager: ObservableObject {
    
    // MARK: - Published State
    
    /// All available views (built-in + user-created)
    @Published var views: [NamedView] = [.all]
    
    /// Currently selected view
    @Published var selectedView: NamedView = .all
    
    // MARK: - Private
    
    private let storageKey = "namedViews"
    
    // MARK: - Initialization
    
    init() {
        loadViews()
    }
    
    // MARK: - View Management
    
    /// Add a new view
    func addView(_ view: NamedView) {
        guard !views.contains(where: { $0.id == view.id }) else { return }
        views.append(view)
        saveViews()
    }
    
    /// Update an existing view
    func updateView(_ view: NamedView) {
        guard let index = views.firstIndex(where: { $0.id == view.id }) else { return }
        views[index] = view
        
        // Update selected if it's the same view
        if selectedView.id == view.id {
            selectedView = view
        }
        
        saveViews()
    }
    
    /// Remove a view (cannot remove built-in views)
    func removeView(_ view: NamedView) {
        guard !view.isBuiltIn else { return }
        views.removeAll { $0.id == view.id }
        
        // Reset selection if removed view was selected
        if selectedView.id == view.id {
            selectedView = .all
        }
        
        saveViews()
    }
    
    /// Move views (for reordering)
    func moveViews(from source: IndexSet, to destination: Int) {
        views.move(fromOffsets: source, toOffset: destination)
        saveViews()
    }
    
    /// Select a view
    func selectView(_ view: NamedView) {
        selectedView = view
    }
    
    // MARK: - Persistence
    
    private func loadViews() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([NamedView].self, from: data) else {
            // Start with default views
            views = [.all]
            return
        }
        
        // Ensure "All" is always first
        let loadedViews = decoded.filter { !$0.isBuiltIn }
        views = [.all] + loadedViews
    }
    
    private func saveViews() {
        // Only save user-created views
        let toSave = views.filter { !$0.isBuiltIn }
        if let encoded = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
