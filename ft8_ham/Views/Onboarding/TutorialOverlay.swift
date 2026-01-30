//
//  TutorialOverlay.swift
//  ft8_ham
//
//  Created by Pablo Turrion on 14/12/25.
//

import SwiftUI

struct TutorialOverlay: View {
    let highlightedFrame: CGRect
    let text: String
    let onDismiss: () -> Void

    let cornerRadius: CGFloat = 12
    let spotlightMinHeight: CGFloat = 60

    @State private var animateCircle: Bool = false
    @State private var circleOpacity: Double = 1.0

    var body: some View {
        GeometryReader { geo in
            let spotlightFrame = highlightedFrame == .zero
                ? CGRect(x: geo.size.width, y: geo.size.height, width: 1, height: 1)
                : CGRect(
                    x: highlightedFrame.minX,
                    y: highlightedFrame.minY,
                    width: highlightedFrame.width,
                    height: max(highlightedFrame.height, spotlightMinHeight)
                )

            let circleStart = CGPoint(
                x: highlightedFrame.maxX - 30 - highlightedFrame.width / 8,
                y: highlightedFrame.minY * 1.35
            )

            let circleEnd = CGPoint(
                x: highlightedFrame.midX - highlightedFrame.width / 8,
                y: highlightedFrame.minY * 1.35
            )

            ZStack {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .frame(
                                        width: spotlightFrame.width,
                                        height: spotlightFrame.height
                                    )
                                    .position(
                                        x: spotlightFrame.midX,
                                        y: spotlightFrame.midY
                                    )
                                    .blendMode(.destinationOut)
                            )
                    )
                    .compositingGroup()

                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .frame(width: spotlightFrame.width / 4, height: spotlightFrame.height)
                    .position(x: spotlightFrame.maxX - spotlightFrame.width / 8,
                              y: spotlightFrame.midY)

                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 50, height: 50)
                    .position(animateCircle ? circleEnd : circleStart)
                    .opacity(circleOpacity)
                    .onAppear {
                        animateCircleLoop(from: circleStart, to: circleEnd)
                    }

                VStack(spacing: 12) {
                    Spacer()
                        .frame(height: spotlightFrame.maxY + 12)

                    Text(LocalizedStringKey(text))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(12)
                        .frame(maxWidth: geo.size.width * 0.8)
                        .shadow(radius: 5)

                    Spacer()

                    Button(action: onDismiss) {
                        Text("Got it")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: highlightedFrame)
        }
    }

    private func animateCircleLoop(from start: CGPoint, to end: CGPoint) {
        circleOpacity = 1.0
        animateCircle = false

        withAnimation(.linear(duration: 2.0)) {
            animateCircle = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                circleOpacity = 0.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                animateCircleLoop(from: start, to: end)
            }
        }
    }
}
