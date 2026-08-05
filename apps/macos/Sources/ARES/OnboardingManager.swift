//
//  OnboardingManager.swift
//  ARES
//
//  Manages first-run onboarding state and JaegerAI dependency detection
//

import Foundation
import SwiftUI

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()
    
    @Published var needsOnboarding: Bool = true
    @Published var agentName: String = "Jarvis"
    @Published var agentRole: String = "AI Butler & Companion"
    @Published var selectedCharacterId: String? = "jarvis"
    @Published var selectedAwakeModel: String? = "qwen2.5-coder:7b"
    @Published var selectedAsleepModel: String? = "llama3.2:1b"
    @Published var networkMode: String = "local"
    @Published var autoLaunchWebUI: Bool = true
    @Published var enableTailscale: Bool = false
    
    @Published var isJaegerInstalled: Bool = false
    @Published var jaegerStatusText: String = "Checking Jaeger AI dependency..."
    
    private let onboardingCompletedKey = "ares_onboarding_completed"
    
    init() {
        checkOnboardingStatus()
        Task {
            await fetchJaegerDefaults()
        }
    }
    
    func checkOnboardingStatus() {
        let completed = UserDefaults.standard.bool(forKey: onboardingCompletedKey)
        self.needsOnboarding = !completed
    }
    
    func markCompleted() {
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
        needsOnboarding = false
    }
    
    func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: onboardingCompletedKey)
        needsOnboarding = true
    }
    
    func fetchJaegerDefaults() async {
        guard let url = URL(string: "http://localhost:8788/api/onboarding/companion/defaults") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                self.jaegerStatusText = "Jaeger AI: Local Standalone"
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            
            if let available = json["available"] as? Bool, available {
                self.isJaegerInstalled = true
                self.jaegerStatusText = "✓ Jaeger AI Installed & Connected"
            } else {
                self.isJaegerInstalled = false
                self.jaegerStatusText = "Jaeger AI: Local Standalone"
            }
            
            if let recAwake = json["recommended_model"] as? String, !recAwake.isEmpty {
                self.selectedAwakeModel = recAwake
            }
            if let recAsleep = json["recommended_asleep_model"] as? String, !recAsleep.isEmpty {
                self.selectedAsleepModel = recAsleep
            }
        } catch {
            self.jaegerStatusText = "Jaeger AI: Active"
        }
    }
    
    func saveOnboardingState(characterId: String, awakeModel: String, asleepModel: String) async throws {
        guard let url = URL(string: "http://localhost:8788/api/onboarding/companion/create") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "character_id": characterId,
            "name": agentName,
            "display_name": agentName,
            "personality": agentRole,
            "make_default": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
    }
}
