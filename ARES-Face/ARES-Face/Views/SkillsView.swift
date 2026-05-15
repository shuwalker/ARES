import SwiftUI

/// Skill browser — lists all Hermes skills with category groups.
/// From OS1 pattern: flat list with category badges, detail on click.
struct SkillsView: View {
    @State private var skills: [Skill] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSkill: Skill?
    @State private var searchText = ""
    
    var categories: [String: [Skill]] {
        Dictionary(grouping: skills.filter { s in
            searchText.isEmpty || s.name.localizedCaseInsensitiveContains(searchText) || s.description.localizedCaseInsensitiveContains(searchText)
        }, by: { $0.category })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search skills...", text: $searchText).textFieldStyle(.plain)
                    .onSubmit { }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            
            if isLoading {
                Spacer()
                ProgressView("Loading skills...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { loadSkills() }.buttonStyle(.bordered)
                }
                Spacer()
            } else {
                List {
                    ForEach(categories.keys.sorted(), id: \.self) { category in
                        Section(category) {
                            ForEach(categories[category] ?? []) { skill in
                                SkillRow(skill: skill)
                                    .onTapGesture { selectedSkill = skill }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { loadSkills() }
        .sheet(item: $selectedSkill) { skill in
            SkillDetailView(skill: skill)
        }
    }
    
    private func loadSkills() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                skills = try await HermesDashboardService.shared.listSkills()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

struct SkillRow: View {
    let skill: Skill
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(skill.enabled ? .teal : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.body.weight(.medium))
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if !skill.enabled {
                Text("disabled").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SkillDetailView: View {
    let skill: Skill
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(skill.name).font(.title2.weight(.bold))
                    Text(skill.category).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                Text(skill.description)
                    .padding()
            }
        }
        .frame(width: 500, height: 400)
    }
}