//
//  RotaryEncoderDeck.swift
//  VirtualEspressoMachine
//

import SwiftUI

public struct RotaryEncoderDeck: View {
    let knobAngle: Double
    let accentColor: Color
    let isDisabled: Bool
    
    let onTurnLeft: () -> Void
    let onTurnRight: () -> Void
    let onPushCenter: () -> Void
    let onDragKnob: (Double) -> Void
    
    public init(
        knobAngle: Double,
        accentColor: Color,
        isDisabled: Bool = false,
        onTurnLeft: @escaping () -> Void,
        onTurnRight: @escaping () -> Void,
        onPushCenter: @escaping () -> Void,
        onDragKnob: @escaping (Double) -> Void
    ) {
        self.knobAngle = knobAngle
        self.accentColor = accentColor
        self.isDisabled = isDisabled
        self.onTurnLeft = onTurnLeft
        self.onTurnRight = onTurnRight
        self.onPushCenter = onPushCenter
        self.onDragKnob = onDragKnob
    }
    
    public var body: some View {
        HStack(spacing: 36) {
            // Step Left
            Button(action: onTurnLeft) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isDisabled)
            
            // Physical Rotary Dial
            ZStack {
                // Outer Knurled Ring
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 3)
                    .background(
                        Circle().fill(Color(red: 0.12, green: 0.12, blue: 0.14))
                    )
                    .frame(width: 104, height: 104)
                
                // 12 Bezel Detents
                ForEach(0..<12, id: \.self) { tick in
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 2, height: 6)
                        .offset(y: -46)
                        .rotationEffect(.degrees(Double(tick) * 30))
                }
                
                // Rotating Notch Position Indicator
                Circle()
                    .fill(accentColor)
                    .frame(width: 7, height: 7)
                    .offset(y: -38)
                    .rotationEffect(.degrees(knobAngle))
                
                // Pure Hardware Center Push Button (NO TEXT)
                Button(action: onPushCenter) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.2))
                        Circle()
                            .stroke(accentColor.opacity(0.7), lineWidth: 2)
                            .frame(width: 52, height: 52)
                        Image(systemName: "power")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(accentColor)
                    }
                    .frame(width: 60, height: 60)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
            .gesture(
                DragGesture()
                    .onChanged { val in
                        onDragKnob(val.translation.width)
                    }
                    .onEnded { _ in
                        onDragKnob(0)
                    }
            )
            
            // Step Right
            Button(action: onTurnRight) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isDisabled)
        }
    }
}
