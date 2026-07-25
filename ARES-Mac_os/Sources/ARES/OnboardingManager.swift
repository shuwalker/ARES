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
    @Published var selectedCharacterId: String?
    @Published var selectedAwakeModel: String?
    @Published var selectedAsleepModel: String?
    @Published var agentName: String = "Jarvis"
    @Published var agentRole: String = "Your personal AI assistant"
    
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
        guard let url = URL(string: "http://localhost:8787/api/jaeger-onboarding/create-instance") else {
            throw OnboardingError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "character_id": characterId,
            "agent_name": agentName,
            "role": agentRole,
            "awake_model": awakeModel,
            "asleep_model": asleepModel
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorResponse["error"] as? String {
                throw OnboardingError.apiError(error)
            }
            throw OnboardingError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        
        // Parse success response
        if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = jsonResponse["success"] as? Bool, success {
            // Store the instance info
            defaults.set(characterId, forKey: "jaeger_character_id")
            defaults.set(awakeModel, forKey: "jaeger_awake_model")
            defaults.set(asleepModel, forKey: "jaeger_asleep_model")
            defaults.set(agentName, forKey: "jaeger_agent_name")
            return
        }
        
        throw OnboardingError.parseError
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
