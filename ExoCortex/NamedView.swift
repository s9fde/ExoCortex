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
        NamedView(name: "Work", filter: "#work", icon: "briefcase"),
        NamedView(name: "Personal", filter: "#personal", icon: "person"),
    ]
}

// MARK: - iCloud Availability

/// Set to true when Apple Developer Program enrollment is active.
/// When false, falls back to local UserDefaults storage.
/// Change to `true` after enrollment is confirmed (typically 24-48 hours).
private let iCloudSyncEnabled = false

// MARK: - Views Manager

/// Manages the collection of named views, persisting to iCloud via NSUbiquitousKeyValueStore.
/// This enables automatic sync of views between macOS and iOS devices.
/// Falls back to UserDefaults when iCloud is not available.
@MainActor
@Observable
final class ViewsManager {
    
    // MARK: - State
    
    /// All available views (built-in + user-created)
    var views: [NamedView] = [.all]
    
    /// Currently selected view
    var selectedView: NamedView = .all
    
    // MARK: - Private
    
    private let storageKey = "namedViews"
    private let iCloudStore = NSUbiquitousKeyValueStore.default
    // Note: nonisolated(unsafe) is needed for cleanup in deinit
    // This is safe because deinit is not reentrant and no other code accesses it
    private nonisolated(unsafe) var notificationObserver: (any NSObjectProtocol)?
    
    // MARK: - Initialization
    
    init() {
        loadViews()
        if iCloudSyncEnabled {
            setupiCloudObserver()
            iCloudStore.synchronize()
        }
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
    
    // MARK: - iCloud Sync
    
    /// Set up observer for external iCloud changes
    private func setupiCloudObserver() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: iCloudStore,
            queue: .main
        ) { [weak self] notification in
            // Extract userInfo on callback thread before crossing actor boundary
            guard let userInfo = notification.userInfo,
                  let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
                  let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] else {
                return
            }
            Task { @MainActor in
                self?.handleiCloudChange(changeReason: changeReason, changedKeys: changedKeys)
            }
        }
    }
    
    /// Handle changes from another device
    private func handleiCloudChange(changeReason: Int, changedKeys: [String]) {
        // Check if our key was affected
        guard changedKeys.contains(storageKey) else { return }
        
        switch changeReason {
        case NSUbiquitousKeyValueStoreServerChange,
             NSUbiquitousKeyValueStoreInitialSyncChange:
            // Reload views from iCloud
            loadViews()
        case NSUbiquitousKeyValueStoreQuotaViolationChange:
            // Storage quota exceeded - continue with local data
            break
        case NSUbiquitousKeyValueStoreAccountChange:
            // iCloud account changed - reload to get new account's data
            loadViews()
        default:
            break
        }
    }
    
    // MARK: - Persistence
    
    private func loadViews() {
        let data: Data?
        
        if iCloudSyncEnabled {
            // Try iCloud first, fall back to UserDefaults for migration
            if let iCloudData = iCloudStore.data(forKey: storageKey) {
                data = iCloudData
            } else if let localData = UserDefaults.standard.data(forKey: storageKey) {
                // Migration: move existing local data to iCloud
                data = localData
                iCloudStore.set(localData, forKey: storageKey)
                iCloudStore.synchronize()
                // Clear local copy after migration
                UserDefaults.standard.removeObject(forKey: storageKey)
            } else {
                data = nil
            }
        } else {
            // iCloud disabled - use local UserDefaults only
            data = UserDefaults.standard.data(forKey: storageKey)
        }
        
        guard let data = data,
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
            if iCloudSyncEnabled {
                iCloudStore.set(encoded, forKey: storageKey)
                iCloudStore.synchronize()
            } else {
                UserDefaults.standard.set(encoded, forKey: storageKey)
            }
        }
    }
}
