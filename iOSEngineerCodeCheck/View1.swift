//
//  View1.swift
//  iOSEngineerCodeCheck
//
//  Created by GitHub Copilot on 2026/05/19.
//

import SwiftUI

struct View1: View {

    private struct Response: Decodable {
        let items: [DataItem]
    }

    @State private var data: [DataItem] = []
    @State private var saved: [DataItem] = []
    @State private var text = "GitHubのリポジトリを検索できるよー"
    @State private var flag = false
    @State private var index = 1
    @State private var once = false
    @FocusState private var focus: Bool

    var body: some View {
        TabView(selection: $index) {
            NavigationStack {
                View2(
                    data: $saved,
                    flag: .constant(false),
                    mode: true,
                    message: "検索ボタンをタップして"
                )
                .navigationTitle("Bookmarks")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "bookmark.fill")
                Text("Bookmark")
            }
            .tag(0)

            NavigationStack {
                View2(
                    data: $data,
                    flag: $flag,
                    mode: false,
                    header: AnyView(field),
                    message: "GitHubのリポジトリを検索できるよー"
                )
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Image(systemName: "magnifyingglass.circle.fill")
                Text("Search")
            }
            .tag(1)
        }
        .tint(.black)
        .background(.ultraThinMaterial)
        .onChange(of: index) { _, newValue in
            if newValue == 1 {
                if text == "GitHubのリポジトリを検索できるよー" {
                    text = ""
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    focus = true
                }
            } else {
                focus = false
            }
        }
        .onAppear {
            loadBookmarksIfNeeded()
        }
        .onChange(of: data) { _, newValue in
            syncBookmarksFromSearch(newValue)
        }
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                if !data.isEmpty {
                    data = []
                }
            }
        }
    }

    private var field: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.search)
            .focused($focus)
            .onTapGesture {
                if text == "GitHubのリポジトリを検索できるよー" {
                    text = ""
                }
            }
            .onSubmit {
                search()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
    }

    private func search() {
        let trimmedQuery = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedQuery.count == 0 || trimmedQuery == "GitHubのリポジトリを検索できるよー" {
            return
        }

        flag = true
        Task {
            do {
                let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let url = URL(string: "https://api.github.com/search/repositories?q=\(encodedQuery)")!

                let (data, _) = try await URLSession.shared.data(from: url)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(Response.self, from: data)

                await MainActor.run {
                    self.data = response.items
                    syncSearchBookmarkState()
                    flag = false
                }
            } catch {
                await MainActor.run {
                    flag = false
                }
            }
        }
    }

    private func isBookmarked(_ repository: DataItem) -> Bool {
        saved.contains { $0.fullName == repository.fullName }
    }

    private func toggleBookmark(_ repository: DataItem) {
        if let idx = saved.firstIndex(where: { $0.fullName == repository.fullName }) {
            saved.remove(at: idx)
        } else {
            var newRepository = repository
            newRepository.marked = true
            saved.append(newRepository)
        }

        saveBookmarks()
        syncSearchBookmarkState()
    }

    private func loadBookmarksIfNeeded() {
        if once {
            return
        }

        once = true

        if let data = UserDefaults.standard.data(forKey: "data"),
           let value = try? JSONDecoder().decode([DataItem].self, from: data) {
            saved = value
            syncSearchBookmarkState()
        }

        syncSearchBookmarkState()
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: "data")
        }
    }

    private func syncBookmarksFromSearch(_ updatedRepositories: [DataItem]) {
        var changed = false

        for repository in updatedRepositories {
            let index = saved.firstIndex { $0.fullName == repository.fullName }

            if repository.marked == true {
                if let index {
                    if saved[index].marked != true {
                        saved[index].marked = true
                        changed = true
                    }
                } else {
                    var newRepository = repository
                    newRepository.marked = true
                    saved.append(newRepository)
                    changed = true
                }
            } else if let index {
                saved.remove(at: index)
                changed = true
            }
        }

        if changed {
            saveBookmarks()
        }
    }

    private func syncSearchBookmarkState() {
        for i in data.indices {
            data[i].marked = isBookmarked(data[i])
        }
    }
}

#Preview {
    View1()
}
