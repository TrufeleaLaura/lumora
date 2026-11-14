import SwiftUI

/// "Find a tool": goals first, then every tool grouped by category, searchable in plain words
/// ("teeth", "remove", "brighter").
struct ToolFinderView: View {
    @ObservedObject var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Hit: Identifiable {
        let title: String
        let tool: StudioTool
        var id: String { title + tool.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("Start with a goal") {
                        ForEach(Recipe.all) { recipe in
                            goalLink(recipe)
                        }
                    }
                    .drRow()
                    ForEach(StudioCategory.allCases) { category in
                        Section(category.title) {
                            ForEach(category.tools) { tool in
                                Button { open(tool) } label: {
                                    FinderRow(title: tool.title, detail: tool.summary)
                                }
                                .accessibilityIdentifier("find.\(tool.rawValue)")
                            }
                        }
                        .drRow()
                    }
                } else {
                    let results = search(query)
                    if results.goals.isEmpty && results.tools.isEmpty {
                        Text("No tool matches \u{201C}\(query)\u{201D}. Try \u{201C}skin\u{201D}, \u{201C}sky\u{201D} or \u{201C}crop\u{201D}.")
                            .font(Typeface.jost(14))
                            .foregroundStyle(Darkroom.stone)
                            .listRowBackground(Color.clear)
                    }
                    if !results.goals.isEmpty {
                        Section("Goals") {
                            ForEach(results.goals) { recipe in
                                goalLink(recipe)
                            }
                        }
                        .drRow()
                    }
                    if !results.tools.isEmpty {
                        Section("Tools") {
                            ForEach(results.tools) { hit in
                                Button { open(hit.tool) } label: {
                                    FinderRow(title: hit.title, detail: hit.tool.path.uppercased(), detailIsCode: true)
                                }
                            }
                        }
                        .drRow()
                    }
                }
            }
            .drFormStyle()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Try \u{201C}teeth\u{201D}, \u{201C}remove\u{201D} or \u{201C}brighter\u{201D}")
            .navigationTitle("FIND A TOOL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func goalLink(_ recipe: Recipe) -> some View {
        NavigationLink {
            RecipeView(recipe: recipe) {
                Button {
                    session.startGuide(recipe)
                    dismiss()
                } label: {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        } label: {
            FinderRow(title: recipe.title, detail: recipe.subtitle, showsChevron: false)
        }
        .accessibilityIdentifier("findgoal.\(recipe.id)")
    }

    private func open(_ tool: StudioTool) {
        session.studioTool = tool
        dismiss()
    }

    private func search(_ text: String) -> (goals: [Recipe], tools: [Hit]) {
        let words = text.lowercased().split(separator: " ").map(String.init)
        func matches(_ haystack: String) -> Bool {
            let lowered = haystack.lowercased()
            return words.allSatisfy { lowered.contains($0) }
        }
        var hits: [Hit] = []
        var titles = Set<String>()
        for shortcut in ToolShortcut.all where matches(shortcut.title + " " + shortcut.keywords) {
            hits.append(Hit(title: shortcut.title, tool: shortcut.tool))
            titles.insert(shortcut.title)
        }
        for tool in StudioTool.allCases where !titles.contains(tool.title) {
            if matches([tool.title, tool.summary, tool.keywords, tool.category.title].joined(separator: " ")) {
                hits.append(Hit(title: tool.title, tool: tool))
            }
        }
        let goals = Recipe.all.filter { matches($0.title + " " + $0.subtitle) }
        return (goals, Array(hits.prefix(14)))
    }
}

/// A Settings-style row: a title, one line of detail and a chevron.
struct FinderRow: View {
    let title: String
    let detail: String
    var detailIsCode = false
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typeface.jost(16))
                    .foregroundStyle(Darkroom.cream)
                if detailIsCode {
                    Text(detail)
                        .filmCode(9.5)
                        .foregroundStyle(Darkroom.stone)
                } else {
                    Text(detail)
                        .font(Typeface.jost(13))
                        .foregroundStyle(Darkroom.stone)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Darkroom.stone)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// A recipe: its steps in order, then the actions that start it.
struct RecipeView<Actions: View>: View {
    let recipe: Recipe
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(recipe.title)
                    .font(Typeface.cormorant(38, weight: 500))
                    .foregroundStyle(Darkroom.cream)
                    .padding(.top, 18)
                Text(recipe.summary)
                    .font(Typeface.jost(15))
                    .foregroundStyle(Darkroom.stone)
                    .lineSpacing(3)
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(format: "%02d", index + 1))
                                .filmCode(11)
                                .foregroundStyle(Darkroom.safelight)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title)
                                    .font(Typeface.jost(16))
                                    .foregroundStyle(Darkroom.cream)
                                Text(step.tool.path.uppercased())
                                    .filmCode(9.5)
                                    .foregroundStyle(Darkroom.stone)
                                Text(step.tip)
                                    .font(Typeface.jost(13))
                                    .foregroundStyle(Darkroom.stone)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .overlay(alignment: .top) {
                            if index > 0 {
                                Rectangle().fill(Darkroom.line).frame(height: 0.5).padding(.leading, 16)
                            }
                        }
                    }
                }
                .background(Darkroom.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 24)
                VStack(spacing: 10) {
                    actions
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Darkroom.ink.ignoresSafeArea())
    }
}
