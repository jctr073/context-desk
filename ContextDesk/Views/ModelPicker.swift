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

            Divider()

            Text("API keys are checked in shell profiles and inherited environment.")
                .font(.system(size: 11))
                .foregroundColor(palette.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
        .padding(.vertical, 6)
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
            if !hasKey {
                HStack(spacing: 4) {
                    Image(systemName: "circle")
                        .font(.system(size: 10, weight: .regular))
                    Text("No key")
                        .font(.system(size: 11))
                }
                .foregroundColor(palette.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)

        ForEach(AIModel.models(for: provider)) { model in
            ModelRow(
                model: model,
                isSelected: state.model == model,
                isLocked: !hasKey,
                palette: palette
            ) {
                if hasKey {
                    state.model = model
                } else {
                    state.startAddingKey(provider)
                }
                isOpen = false
            }
        }
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

private struct ModelRow: View {
    let model: AIModel
    let isSelected: Bool
    let isLocked: Bool
    let palette: Palette
    let action: () -> Void

    @State private var isHovered = false

    private var nameColor: Color {
        if isLocked { return palette.muted }
        return isSelected ? palette.text : palette.text.opacity(0.85)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isSelected ? palette.accent : palette.muted.opacity(0.45))
                    .frame(width: 6, height: 6)
                    .frame(width: 16)
                Text(model.name)
                    .font(.system(size: 13))
                    .foregroundColor(nameColor)
                Spacer()
                if isLocked {
                    Image(systemName: "lock")
                        .font(.system(size: 11))
                        .foregroundColor(palette.muted.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
