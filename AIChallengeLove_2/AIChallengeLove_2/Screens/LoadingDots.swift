//
//  LoadingDots.swift
//  AI_Challenge_Love_2
//
//  Created by Bolyachev Rostislav on 12/8/25.
//

import SwiftUI

struct LoadingDots: View {
    @State private var scales: [CGFloat] = [1.0, 1.0, 1.0]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .scaleEffect(scales[index])
            }
        }
        .padding()
        .background(Color.blue.opacity(0.3))
        .cornerRadius(10)
        .onAppear {
            for index in 0..<3 {
                withAnimation(
                    Animation.easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2)
                ) {
                    scales[index] = 1.4
                }
            }
        }
        .onDisappear {
            scales = [1.0, 1.0, 1.0]
        }
    }
}

#Preview() {
    LoadingDots()
}
