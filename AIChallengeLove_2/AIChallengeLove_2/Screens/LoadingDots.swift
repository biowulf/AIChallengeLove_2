//
//  LoadingDots.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/8/25.
//

import SwiftUI

struct LoadingDots: View {
    @State private var dotsOpacity: [CGFloat] = Array(repeating: 1.0, count: 3)
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotsOpacity.count, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .opacity(dotsOpacity[index])
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .padding()
        .background(Color.blue.opacity(0.3))
        .cornerRadius(10)
        .onAppear {
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}

#Preview() {
    LoadingDots()
}
