//
//  OnboardingManager.swift
//  ARES
//
//  Manages first-run onboarding state
//

import Foundation
import SwiftUI

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()
    
    @Published var needsOnboarding: Bool = true
    @Published var isCompleting: Bool = false
    
    private let onboardingCompletedKey = "onboarding_completed"
    
    private init() {
        // Check if onboarding was already completed
        needsOnboarding = !UserDefaults.standard.bool(forKey: onboardingCompletedKey)
    }
    
    func markCompleted() {
        UserDefaults.standard.set(true, forKey: onboardingCompletedKey)
        needsOnboarding = false
    }
    
    func reset() {
        UserDefaults.standard.removeObject(forKey: onboardingCompletedKey)
        needsOnboarding = true
    }
}
