import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var profiles: [ProfileInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var newProfileName = ""
    @State private var profileToDelete: ProfileInfo?
    @State private var showDeleteConfirmation = false

    var body: some View {
        HermesPageContainer(width: .analytics) {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: "Profiles",
                    subtitle: "Manage Hermes profiles. Each profile has isolated sessions, skills, memory, and configuration. Switching profiles restarts the gateway."
                )

                profilesContent
            }
            .overlay(alignment: .topTrailing) {
                if isLoading && profiles.isEmpty {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await loadProfiles()
        }
        .sheet(isPresented: $showCreateSheet) {
            createProfileSheet
        }
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    Task { await deleteProfile(profile) }
                }
            }
        } message: {
            if let profile = profileToDelete {
                Text("Are you sure you want to delete the profile \"\(profile.name)\"? This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private var profilesContent: some View {
        if isLoading && profiles.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading profiles…", minHeight: 320)
            }
        } else if let error = errorMessage {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load profiles",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else if profiles.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No profiles found",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Connect to a local Hermes instance to manage profiles.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else {
            profilesLoadedView
        }
    }

    private var profilesLoadedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(profiles.count) profile\(profiles.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Profile", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            HermesSurfacePanel {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(profiles) { profile in
                        profileRow(profile: profile)
                        if profile.id != profiles.last?.id {
                            Divider()
                        }
                    }
                }
            }

            // Current profile note
            if let activeProfile = appState.activeConnection?.resolvedHermesProfileName {
                HermesSurfacePanel {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("Active profile: \(activeProfile). Switch profiles from the sidebar dropdown.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func profileRow(profile: ProfileInfo) -> some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: profile.isDefault == true ? "star.circle.fill" : "person.crop.circle")
                .font(.title2)
                .foregroundStyle(profile.isDefault == true ? .yellow : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.headline)

                    if profile.isDefault == true {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.2), in: Capsule())
                            .foregroundStyle(.yellow)
                    }

                    if profile.hasEnv == true {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    } else if profile.hasEnv == false {
                        Text("Not Found")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red.opacity(0.2), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }

                if let path = profile.path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    if let model = profile.model {
                        Label(model, systemImage: "brain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let skillCount = profile.skillCount, skillCount > 0 {
                        Label("\(skillCount) skills", systemImage: "book")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if profile.isDefault != true {
                Button {
                    profileToDelete = profile
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete profile")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private var createProfileSheet: some View {
        VStack(spacing: 16) {
            Text("Create Profile")
                .font(.headline)

            TextField("Profile name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showCreateSheet = false
                    newProfileName = ""
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    Task { await createProfile() }
                    showCreateSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    // MARK: - Data Loading

    private func loadProfiles() async {
        guard appState.activeConnection != nil, appState.dashboardAPIAvailable else {
            errorMessage = "Profile management requires an active connection."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await appState.dashboardAPIService.fetchProfiles()
            profiles = response.profiles
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func createProfile() async {
        let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isLoading = true
        newProfileName = ""

        do {
            try await appState.dashboardAPIService.createProfile(name: name)
            await loadProfiles()
        } catch {
            errorMessage = "Failed to create profile: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func deleteProfile(_ profile: ProfileInfo) async {
        isLoading = true

        do {
            try await appState.dashboardAPIService.deleteProfile(name: profile.name)
            await loadProfiles()
        } catch {
            errorMessage = "Failed to delete profile: \(error.localizedDescription)"
            isLoading = false
        }
    }
}