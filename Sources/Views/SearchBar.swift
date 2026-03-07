import SwiftUI

/// Floating search bar for finding text within conversation (Cmd+F)
struct SearchBar: View {
    @Binding var searchText: String
    @Binding var isPresented: Bool
    let matchCount: Int
    @Binding var currentMatchIndex: Int
    @EnvironmentObject private var theme: ThemeEngine
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(theme.muted)

            TextField("Search conversation...", text: $searchText)
                .textFieldStyle(.plain)
                .font(Typography.body)
                .foregroundColor(theme.primary)
                .focused($isFocused)

            if !searchText.isEmpty {
                // Result count
                Text(matchCount > 0
                    ? "\(currentMatchIndex + 1) of \(matchCount)"
                    : "No results")
                    .font(Typography.caption)
                    .foregroundColor(matchCount > 0 ? theme.secondary : theme.muted)
                    .fixedSize()

                // Navigation buttons
                Button {
                    if matchCount > 0 {
                        currentMatchIndex = (currentMatchIndex - 1 + matchCount) % matchCount
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(matchCount > 0 ? theme.primary : theme.muted)
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)

                Button {
                    if matchCount > 0 {
                        currentMatchIndex = (currentMatchIndex + 1) % matchCount
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(matchCount > 0 ? theme.primary : theme.muted)
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)
            }

            Button {
                searchText = ""
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(theme.sky.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
        .onAppear { isFocused = true }
        .onKeyPress(.escape) {
            searchText = ""
            isPresented = false
            return .handled
        }
    }
}
