//
//  TextEditorView.swift
//  Feather
//
//  Created by David Wojcik III on 11/9/25.
//

import SwiftUI

struct TextEditorView: View {
    let fileURL: URL
    @State var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var showSavedOverlay = false

    var body: some View {
        NavigationStack {
            ZStack {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))

                // Simple transient "Saved" alert overlay
                if showSavedOverlay {
                    VStack {
                        Spacer()
                        Text("Saved")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                        Spacer()
                    }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: showSavedOverlay)
                }
            }
            .navigationTitle(fileURL.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveFile() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func saveFile() {
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            showSavedOverlay = true

            // Hide the alert and close view after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation { showSavedOverlay = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                dismiss()
            }

        } catch {
            print("Failed to save: \(error.localizedDescription)")
        }
    }
}
