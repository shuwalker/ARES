//
//  OnboardingManager.swift
//  ARES
//
//  Manages first-run onboarding state for JaegerAI setup
//

import Foundation
import SwiftUI

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()
    
    @Published var needsOnboarding: Bool = false
    @Published var isCompleting: Bool = false
    @Published var onboardingWindowOpen: Bool = false
    
    // Onboarding state
    @Published var selectedCharacterId: String? = "jarvis"
    @Published var selectedAwakeModel: String? = "qwen2.5-coder:7b"
    @Published var selectedAsleepModel: String? = "llama3.2:1b"
    @Published var agentName: String = "Jarvis"
    @Published var agentRole: String = "Your personal AI assistant"
    @Published var networkMode: String = "local" // "local" or "network"
    @Published var enableTailscale: Bool = false
    @Published var autoLaunchWebUI: Bool = true
    
    private let onboardingCompletedKey = "onboarding_completed"
    private let defaults = UserDefaults.standard
    
    private init() {
        let force = defaults.bool(forKey: "ARESForceOnboarding")
        let instancesExist = Self.checkInstancesExist()
        if force || !instancesExist {
            needsOnboarding = true
        } else {
            needsOnboarding = !defaults.bool(forKey: onboardingCompletedKey)
        }
    }

    static func checkInstancesExist() -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let candidatePaths = [
            home.appendingPathComponent("jaeger/.jaeger_os/instances"),
            home.appendingPathComponent(".jaeger/.jaeger_os/instances"),
            home.appendingPathComponent(".jaeger/instances"),
            home.appendingPathComponent(".ares/instances")
        ]
        for path in candidatePaths {
            if let contents = try? fm.contentsOfDirectory(atPath: path.path), !contents.isEmpty {
                return true
            }
        }
        return false
    }
    
    func markCompleted() {
        defaults.set(true, forKey: onboardingCompletedKey)
        needsOnboarding = false
        onboardingWindowOpen = false
    }
    
    func reset() {
        defaults.removeObject(forKey: onboardingCompletedKey)
        needsOnboarding = true
        selectedCharacterId = nil
        selectedAwakeModel = nil
        selectedAsleepModel = nil
    }
    
    func showOnboarding() {
        onboardingWindowOpen = true
        needsOnboarding = true
    }
    
    func saveOnboardingState(characterId: String, awakeModel: String, asleepModel: String) async throws {
        isCompleting = true
        defer { isCompleting = false }
        
        // Call the WebUI API to create the JaegerAI instance
        defaults.set(characterId, forKey: "jaeger_character_id")
        defaults.set(awakeModel, forKey: "jaeger_awake_model")
        defaults.set(asleepModel, forKey: "jaeger_asleep_model")
        defaults.set(agentName, forKey: "jaeger_agent_name")
        defaults.set(networkMode, forKey: "ares_network_mode")
        defaults.set(enableTailscale, forKey: "ares_enable_tailscale")
        defaults.set(autoLaunchWebUI, forKey: "ares_auto_launch_webui")
        
        guard let url = URL(string: "http://localhost:8787/api/jaeger-onboarding/create-instance") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3.0
        
        let payload: [String: Any] = [
            "character_id": characterId,
            "agent_name": agentName,
            "role": agentRole,
            "awake_model": awakeModel,
            "asleep_model": asleepModel,
            "network_mode": networkMode,
            "enable_tailscale": enableTailscale
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, _) = try await URLSession.shared.data(for: request)
        } catch {
            print("[ARES] Saved onboarding configuration locally")
        }
    }
}

enum OnboardingError: LocalizedError {
    case invalidURL
    case apiError(String)
    case httpError(Int)
    case parseError
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let message):
            return "Setup failed: \(message)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .parseError:
            return "Failed to parse response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
