//
//  IPAProgressManager.swift
//  Feather
//
//  Created by David Wojcik III on 11/4/25.
//


import SwiftUI
import Combine

final class IPAProgressManager: ObservableObject {
    static let shared = IPAProgressManager()

    @Published var isShowing = false
    @Published var progress: Double = 0.0
    @Published var name: String = ""

    func show(name: String) {
        withAnimation(.spring()) {
            self.name = name
            self.progress = 0
            self.isShowing = true
        }
    }

    func update(_ value: Double) {
        DispatchQueue.main.async {
            self.progress = value
        }
    }

    func complete() {
        withAnimation(.easeInOut(duration: 0.4)) {
            self.progress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring()) {
                self.isShowing = false
            }
        }
    }
}
