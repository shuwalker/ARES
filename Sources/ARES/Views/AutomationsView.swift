import SwiftUI

// MARK: - Automations View
// Displays all automated systems from ~/.ares/automation-registry.json
// Shows status, schedule, category, and health for each automation

struct AutomationsView: View {
    @State private var registry: AutomationRegistry?
    @State private var isLoading = true
    @State private var selectedCategory: String? = nil
    @State private var searchText = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection
                
                // Category filter
                categoryFilterBar
                
                // Automation cards
                if isLoading {
                    ProgressView("Loading automations...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let reg = registry {
                    let filtered = filteredAutomations(reg.automations)
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { automation in
                                AutomationCard(automation: automation)
                            }
                        }
                    }
                } else {
                    errorState
                }
            }
            .padding()
        }
        .task {
            await loadRegistry()
        }
        .refreshable {
            await loadRegistry()
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Automations")
                    .font(.title)
                    .fontWeight(.bold)
                if let reg = registry {
                    Text("\(reg.automations.count) systems • \(activeCount) active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await loadRegistry() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
    }
    
    // MARK: - Category Filter
    
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip("All", isSelected: selectedCategory == nil)
                    .onTapGesture { selectedCategory = nil }
                
                if let reg = registry {
                    ForEach(Array(reg.categories.keys.sorted()), id: \.self) { key in
                        let cat = reg.categories[key]
                        categoryChip(cat?.label ?? key.capitalized,
                                     color: cat?.color ?? "gray",
                                     icon: cat?.icon ?? "gear",
                                     isSelected: selectedCategory == key)
                            .onTapGesture {
                                selectedCategory = selectedCategory == key ? nil : key
                            }
                    }
                }
            }
        }
    }
    
    private func categoryChip(_ label: String, color: String = "gray", icon: String? = nil, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.controlBackgroundColor))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Filtered Automations
    
    private func filteredAutomations(_ automations: [AutomationRegistry.Automation]) -> [AutomationRegistry.Automation] {
        var result = automations
        
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        
        if !searchText.isEmpty {
            result = result.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return result.sorted { 
            if $0.status != $1.status {
                return $0.status == "active" && $1.status != "active"
            }
            return $0.name < $1.name
        }
    }
    
    // MARK: - States
    
    private var activeCount: Int {
        registry?.automations.filter { $0.status == "active" }.count ?? 0
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("No automations found")
                .font(.headline)
            Text("No automations match the current filter")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Registry not found")
                .font(.headline)
            Text("Ensure ~/.ares/automation-registry.json exists")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Retry") {
                Task { await loadRegistry() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
    
    // MARK: - Load
    
    private func loadRegistry() async {
        isLoading = true
        registry = await AutomationRegistryLoader.loadAsync()
        isLoading = false
    }
}

// MARK: - Automation Card

struct AutomationCard: View {
    let automation: AutomationRegistry.Automation
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: automation.sfSymbol)
                    .font(.title3)
                    .foregroundColor(categoryColor)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(automation.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    statusBadge
                }
                
                Text(automation.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    // Schedule
                    Label {
                        Text(automation.schedule)
                            .font(.caption2)
                    } icon: {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                    
                    Divider()
                        .frame(height: 10)
                    
                    // Type
                    Label {
                        Text(automation.type)
                            .font(.caption2)
                    } icon: {
                        Image(systemName: typeIcon)
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                    
                    if let lastRun = automation.lastRun {
                        Divider()
                            .frame(height: 10)
                        
                        Label {
                            Text(formatLastRun(lastRun))
                                .font(.caption2)
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Status Badge
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(automation.status.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(statusColor)
        }
    }
    
    // MARK: - Helpers
    
    private var statusColor: Color {
        switch automation.status {
        case "active": return .green
        case "inactive": return .gray
        case "error": return .red
        case "disabled": return .secondary
        default: return .gray
        }
    }
    
    private var categoryColor: Color {
        switch automation.category {
        case "cognitive": return .purple
        case "productivity": return .blue
        case "maintenance": return .orange
        case "infrastructure": return .gray
        case "content": return .green
        default: return .gray
        }
    }
    
    private var typeIcon: String {
        switch automation.type {
        case "hermes-cron": return "calendar.badge.clock"
        case "launchd": return "gear"
        case "process": return "terminal"
        case "app": return "app"
        case "script": return "doc.text"
        default: return "gear"
        }
    }
    
    private func formatLastRun(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }
        
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return relative.localizedString(for: date, relativeTo: Date())
    }
}