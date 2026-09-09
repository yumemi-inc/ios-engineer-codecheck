//
//  View2.swift
//  iOSEngineerCodeCheck
//

import SwiftUI

struct View2: View {

    @Binding var data: [DataItem]
    @Binding var flag: Bool
    var mode = false
    var header: AnyView?
    var message = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach($data) { $item in
                    NavigationLink {
                        View3(
                            data: $item
                        )
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.fullName)

                            Spacer(minLength: 16)

                            Text(item.language ?? "")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if let header {
                header
            }
        }
        .overlay {
            if mode {
                if data.isEmpty {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            } else {
                if data.isEmpty && !flag {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay(alignment: .center) {
            if flag {
                ProgressView()
            }
        }
    }
}
