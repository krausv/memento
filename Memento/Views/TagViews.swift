import SwiftData
import SwiftUI

extension TagColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .red: .red
        case .purple: .purple
        case .pink: .pink
        case .teal: .teal
        case .gray: .gray
        }
    }
}

struct TagChip: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tag.color.color.opacity(0.22), in: .capsule)
            .foregroundStyle(tag.color.color)
    }
}

/// Štítky řazené do řádků podle dostupné šířky.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

struct TagChips: View {
    let tags: [Tag]

    var body: some View {
        if !tags.isEmpty {
            FlowLayout { ForEach(tags.sorted { $0.name < $1.name }) { TagChip(tag: $0) } }
        }
    }
}

/// Výběr štítků záznamu s možností založit nový štítek za běhu.
struct TagPicker: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @Binding var selected: [Tag]

    @State private var showing = false
    @State private var newName = ""

    var body: some View {
        HStack(alignment: .top) {
            if selected.isEmpty {
                Text("Bez štítků").foregroundStyle(.secondary)
            } else {
                TagChips(tags: selected)
            }
            Spacer()
            Button("Štítky", systemImage: "tag") { showing = true }
                .popover(isPresented: $showing, arrowEdge: .bottom) { popover }
        }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(allTags) { tag in
                Toggle(isOn: binding(for: tag)) {
                    Label(tag.name, systemImage: "circle.fill").foregroundStyle(tag.color.color, .primary)
                }
            }
            if !allTags.isEmpty { Divider() }
            TextField("Nový štítek", text: $newName)
                .onSubmit(create)
        }
        .padding(12)
        .frame(minWidth: 200)
    }

    private func binding(for tag: Tag) -> Binding<Bool> {
        Binding(
            get: { selected.contains { $0 === tag } },
            set: { on in
                if on { if !selected.contains(where: { $0 === tag }) { selected.append(tag) } }
                else { selected.removeAll { $0 === tag } }
            }
        )
    }

    private func create() {
        guard let name = TagRules.normalized(newName) else { return }
        newName = ""
        if let existing = allTags.first(where: { TagRules.sameName($0.name, name) }) {
            if !selected.contains(where: { $0 === existing }) { selected.append(existing) }
            return
        }
        let tag = Tag(name: name, color: TagColor.allCases[allTags.count % TagColor.allCases.count])
        context.insert(tag)
        try? context.save()
        selected.append(tag)
    }
}

/// Správa štítků v Nastavení: přejmenování, barva, smazání.
struct TagManagerSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var tagToDelete: Tag?

    var body: some View {
        Section("Štítky") {
            if tags.isEmpty {
                Text("Štítky vytvoříš při úpravě záznamu nebo poznámky.").foregroundStyle(.secondary)
            }
            ForEach(tags) { tag in
                TagRow(tag: tag, delete: { tagToDelete = tag })
            }
        }
        .confirmationDialog(
            "Smazat štítek „\(tagToDelete?.name ?? "")“?",
            isPresented: Binding(get: { tagToDelete != nil }, set: { if !$0 { tagToDelete = nil } }),
            presenting: tagToDelete
        ) { tag in
            Button("Smazat", role: .destructive) {
                context.delete(tag)
                try? context.save()
            }
            Button("Zrušit", role: .cancel) {}
        } message: { tag in
            Text("Štítek se odebere z \(tag.entries.count) záznamů, záznamy zůstanou.")
        }
    }
}

private struct TagRow: View {
    @Environment(\.modelContext) private var context
    @Query private var allTags: [Tag]
    let tag: Tag
    let delete: () -> Void
    @State private var name: String

    init(tag: Tag, delete: @escaping () -> Void) {
        self.tag = tag
        self.delete = delete
        _name = State(initialValue: tag.name)
    }

    private var isTaken: Bool {
        guard let normalized = TagRules.normalized(name) else { return true }
        return allTags.contains { $0 !== tag && TagRules.sameName($0.name, normalized) }
    }

    var body: some View {
        HStack {
            Picker("Barva", selection: Binding(
                get: { tag.color },
                set: { tag.colorName = $0.rawValue; try? context.save() }
            )) {
                ForEach(TagColor.allCases) { color in
                    Label(color.title, systemImage: "circle.fill").foregroundStyle(color.color, .primary).tag(color)
                }
            }
            .labelsHidden()
            .frame(width: 70)
            TextField("Název", text: $name)
                .onSubmit(rename)
            if isTaken, name != tag.name { Text("Název je prázdný nebo už existuje").font(.caption).foregroundStyle(.red) }
            Button("Smazat", systemImage: "trash", role: .destructive, action: delete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    private func rename() {
        guard !isTaken, let normalized = TagRules.normalized(name) else {
            name = tag.name
            return
        }
        tag.name = normalized
        name = normalized
        try? context.save()
    }
}
