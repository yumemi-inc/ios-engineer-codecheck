//
//  View3.swift
//  iOSEngineerCodeCheck
//

import SwiftUI

struct View3: View {

    @Binding var data: DataItem
    @State var description: String = ""

    var body: some View {
        let img = data.owner.avatarUrl

        ScrollView {
            VStack(spacing: 28) {
                AsyncImage(url: URL(string: img)!) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "person.crop.square")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                            .padding(48)
                    default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: 360, maxHeight: 360)
                .frame(maxWidth: .infinity)

                Text(data.fullName)
                    .font(.title)
                    .multilineTextAlignment(.center)

                HStack(alignment: .top) {
                    Text(description)
                        .font(.headline)

                    Spacer(minLength: 24)

                    VStack(alignment: .trailing, spacing: 16) {
                        Text("\(data.stargazersCount) stars")
                        Text("\(data.watchersCount) watchers")
                        Text("\(data.forksCount) forks")
                        Text("\(data.openIssuesCount) open issues")
                    }
                    .font(.subheadline)
                }

                if data.marked == true {
                    Button("Remove from Bookmark") {
                        data.marked = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("Add to Bookmark") {
                        data.marked = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: data, initial: true) { _, newValue in
            if let language = newValue.language {
                description = "Written in \(language)"
            } else {
                description = ""
            }
        }
    }
}
