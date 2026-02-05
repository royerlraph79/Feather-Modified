//
//  IPAHeaderView.swift
//  Feather
//
//  Created by David Wojcik III on 11/4/25.
//

import SwiftUI

struct IPAHeaderView: View {
    @ObservedObject var manager = IPAProgressManager.shared

    var body: some View {
        if manager.isShowing {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.name)
                        .font(.subheadline)
                        .lineLimit(1)

                    ProgressView(value: manager.progress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(Int(manager.progress * 100))%")
                            .contentTransition(.numericText())
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground)) // 🔹 solid light/dark adaptive background
                .overlay(
                    Divider()
                        .background(Color.primary.opacity(0.1)),
                    alignment: .bottom
                )
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: manager.progress)
        }
    }
}
