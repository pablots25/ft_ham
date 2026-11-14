//
//  TutorialSlotModifier.swift
//  ft_ham
//
//  Lets a view show its tutorial only when `GuidanceCoordinator` gives it
//  the turn: one tutorial at a time, never over a launch prompt, and only
//  while the view is on screen.
//

import SwiftUI

private struct TutorialSlotModifier: ViewModifier {
    let tutorial: AppTutorial
    /// Whether the view can show the tutorial right now (e.g. the waterfall
    /// tutorial explains toolbar buttons that only exist while listening).
    let isAvailable: Bool
    @Binding var isPresented: Bool

    @ObservedObject private var coordinator = GuidanceCoordinator.shared

    func body(content: Content) -> some View {
        content
            .onAppear { updateRequest() }
            .onDisappear {
                coordinator.withdraw(tutorial)
                isPresented = false
            }
            .onChange(of: isAvailable) { _ in updateRequest() }
            .onReceive(coordinator.$activeTutorial) { active in
                let show = active == tutorial
                guard show != isPresented else { return }
                withAnimation(.easeInOut(duration: 0.25)) { isPresented = show }
            }
    }

    private func updateRequest() {
        if isAvailable {
            coordinator.request(tutorial)
        } else {
            coordinator.withdraw(tutorial)
        }
    }
}

extension View {
    /// Shows `tutorial` through `isPresented` when it is this view's turn.
    /// Call `GuidanceCoordinator.shared.finish(_:)` when the user dismisses it.
    func tutorialSlot(
        _ tutorial: AppTutorial,
        isAvailable: Bool = true,
        isPresented: Binding<Bool>
    ) -> some View {
        modifier(TutorialSlotModifier(tutorial: tutorial, isAvailable: isAvailable, isPresented: isPresented))
    }
}
