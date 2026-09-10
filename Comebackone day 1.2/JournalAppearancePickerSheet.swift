//
//  JournalAppearancePickerSheet.swift
//  Comebackone day 1.2
//
//  Journal creation AND editing, Apple Journal-style: name + color + icon,
//  with a live circular preview. Floating circular X/checkmark controls
//  instead of a system nav bar, matching this redesign's overall
//  floating-toolbar visual language.
//

import SwiftUI

struct JournalAppearancePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Set when editing an already-existing journal — lets the caller
    /// (JournalListView) know the name to rename/move appearance from if
    /// the saved name differs from this one.
    let existingName: String?
    let onSave: (String, JournalAppearance) -> Void

    @State private var name: String
    @State private var selectedColorOption: JournalColorOption
    @State private var customColor: Color?
    @State private var selectedIcon: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 7)

    init(existingName: String? = nil, existingAppearance: JournalAppearance? = nil, onSave: @escaping (String, JournalAppearance) -> Void) {
        self.existingName = existingName
        self.onSave = onSave
        let appearance = existingAppearance ?? .default
        _name = State(initialValue: existingName ?? "")
        _selectedColorOption = State(initialValue: appearance.color)
        _customColor = State(initialValue: appearance.customColorHex.flatMap { Color(hex: $0) })
        _selectedIcon = State(initialValue: appearance.iconName)
    }

    private var resolvedColor: Color {
        customColor ?? selectedColorOption.color
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Text(existingName == nil ? "New Journal" : "Edit Journal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                previewCircle
                nameField
                colorGrid
                iconGrid
            }
            .padding()
            .padding(.top, 60)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .top) { topControls }
    }

    private var topControls: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(.thickMaterial, in: Circle())
            }

            Spacer()

            Button {
                save()
            } label: {
                Image(systemName: "checkmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(canSave ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.gray.opacity(0.4)), in: Circle())
            }
            .disabled(!canSave)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var previewCircle: some View {
        ZStack {
            Circle()
                .fill(resolvedColor)
                .frame(width: 100, height: 100)
            Image(systemName: selectedIcon)
                .font(.system(size: 36))
                .foregroundStyle(.white)
        }
    }

    private var nameField: some View {
        TextField("Journal Name", text: $name)
            .multilineTextAlignment(.center)
            .font(.title3)
            .padding()
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }

    private var colorGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(JournalColorOption.allCases) { option in
                Button {
                    selectedColorOption = option
                    customColor = nil
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 40, height: 40)
                        .overlay {
                            if customColor == nil && selectedColorOption == option {
                                Circle().stroke(.primary, lineWidth: 3).padding(-4)
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            ColorPicker(
                "Custom color",
                selection: Binding(
                    get: { customColor ?? selectedColorOption.color },
                    set: { customColor = $0 }
                )
            )
            .labelsHidden()
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            .overlay {
                if customColor != nil {
                    Circle().stroke(.primary, lineWidth: 3).padding(-4)
                }
            }
        }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(JournalIconOptions.all, id: \.self) { icon in
                Button {
                    selectedIcon = icon
                } label: {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(selectedIcon == icon ? .white : .secondary)
                        .frame(width: 40, height: 40)
                        .background(
                            selectedIcon == icon ? AnyShapeStyle(resolvedColor) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let appearance = JournalAppearance(
            color: selectedColorOption,
            customColorHex: customColor?.hexString,
            iconName: selectedIcon
        )
        onSave(trimmed, appearance)
        dismiss()
    }
}
