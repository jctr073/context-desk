import SwiftUI

struct ModelPicker: View {
    @ObservedObject var state: AppState
    let palette: Palette

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(palette.accent)
                    .frame(width: 6, height: 6)
                Text(state.model.name)
                    .font(.system(size: 12))
                    .foregroundColor(palette.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(palette.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isOpen ? palette.accent : palette.border,
                            lineWidth: isOpen ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ModelPickerMenu(state: state, palette: palette, isOpen: $isOpen)
        }
    }
}

private struct ModelPickerMenu: View {
    @ObservedObject var state: AppState
    let palette: Palette
    @Binding var isOpen: Bool

    private var catalog: ModelCatalog { state.catalog }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AIProvider.allCases) { provider in
                providerSection(provider)
            }

            Divider()
                .padding(.vertical, 6)

            ForEach(AIProvider.allCases) { provider in
                addKeyRow(for: provider)
            }

            refreshRow

            Divider()

            Text("API keys are checked in shell profiles and inherited environment.")
                .font(.system(size: 11))
                .foregroundColor(palette.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
        .padding(.vertical, 6)
        .onAppear { catalog.onPickerOpened() }
    }

    @ViewBuilder
    private func providerSection(_ provider: AIProvider) -> some View {
        let hasKey = state.hasKey(for: provider)

        HStack {
            Text(provider.sectionLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(palette.muted)
                .kerning(0.4)
            Spacer()
            sectionStatus(provider, hasKey: hasKey)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)

        ForEach(catalog.familyRows(for: provider)) { family in
            ModelFamilyRow(
                family: family,
                displayName: catalog.displayName(for: family),
                isSelected: state.selectedFamily?.id == family.id,
                currentEffort: state.effort(for: family),
                isLocked: !hasKey,
                palette: palette,
                onSelect: {
                    if hasKey {
                        state.selectFamily(family)
                    } else {
                        state.startAddingKey(provider)
                    }
                    isOpen = false
                },
                onEffort: { state.selectEffort($0, for: family) }
            )
        }

        ForEach(catalog.derivedModels(for: provider)) { model in
            ModelFamilyRow(
                family: nil,
                displayName: model.name,
                isSelected: state.model.id == model.id,
                currentEffort: nil,
                isLocked: !hasKey,
                palette: palette,
                onSelect: {
                    if hasKey { state.model = model }
                    isOpen = false
                },
                onEffort: { _ in }
            )
        }
    }

    @ViewBuilder
    private func sectionStatus(_ provider: AIProvider, hasKey: Bool) -> some View {
        if !hasKey {
            HStack(spacing: 4) {
                Image(systemName: "circle")
                    .font(.system(size: 10, weight: .regular))
                Text("No key")
                    .font(.system(size: 11))
            }
            .foregroundColor(palette.muted)
        } else {
            switch catalog.fetchState[provider] ?? .idle {
            case .loading:
                Spinner(color: palette.muted, size: 11)
            case .failed:
                Text("Couldn’t refresh")
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
            case .idle, .ok:
                EmptyView()
            }
        }
    }

    private var refreshRow: some View {
        Button {
            catalog.refresh(force: true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(palette.text)
                    .frame(width: 16)
                Text("Refresh models")
                    .font(.system(size: 13))
                    .foregroundColor(palette.text)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func addKeyRow(for provider: AIProvider) -> some View {
        let hasKey = state.hasKey(for: provider)
        Button {
            state.startAddingKey(provider)
            isOpen = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "key")
                    .font(.system(size: 12))
                    .foregroundColor(palette.text)
                    .frame(width: 16)
                Text("\(hasKey ? "View" : "Set up") \(provider.keyLabel) API key...")
                    .font(.system(size: 13))
                    .foregroundColor(palette.text)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ModelFamilyRow: View {
    /// The family this row represents, or nil for a derived (unrecognized) row.
    let family: ModelFamily?
    let displayName: String
    let isSelected: Bool
    let currentEffort: ReasoningEffort?
    let isLocked: Bool
    let palette: Palette
    let onSelect: () -> Void
    let onEffort: (ReasoningEffort) -> Void

    @State private var isHovered = false

    private var nameColor: Color {
        if isLocked { return palette.muted }
        return isSelected ? palette.text : palette.text.opacity(0.85)
    }

    private var showsEffortMenu: Bool {
        !isLocked && (family?.isReasoning ?? false) && currentEffort != nil
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(isSelected ? palette.accent : palette.muted.opacity(0.45))
                        .frame(width: 6, height: 6)
                        .frame(width: 16)
                    Text(displayName)
                        .font(.system(size: 13))
                        .foregroundColor(nameColor)
                    Spacer(minLength: 8)
                    if isLocked {
                        Image(systemName: "lock")
                            .font(.system(size: 11))
                            .foregroundColor(palette.muted.opacity(0.7))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsEffortMenu, let family, let currentEffort {
                EffortMenu(
                    efforts: family.supportedEfforts,
                    current: currentEffort,
                    palette: palette,
                    onEffort: onEffort
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(rowBackground)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            palette.accent.opacity(0.10)
        } else if isHovered {
            palette.muted.opacity(0.10)
        } else {
            Color.clear
        }
    }
}

private struct EffortMenu: View {
    let efforts: [ReasoningEffort]
    let current: ReasoningEffort
    let palette: Palette
    let onEffort: (ReasoningEffort) -> Void

    var body: some View {
        Menu {
            ForEach(efforts, id: \.self) { effort in
                Button {
                    onEffort(effort)
                } label: {
                    if effort == current {
                        Label(effort.displayLabel, systemImage: "checkmark")
                    } else {
                        Text(effort.displayLabel)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(current.displayLabel)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(palette.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
