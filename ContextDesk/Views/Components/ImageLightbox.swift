import AppKit
import SwiftUI

struct ImageLightbox: View {
    @ObservedObject var state: AppState
    let image: AttachedImage
    let palette: Palette

    var body: some View {
        VStack(spacing: 12) {
            preview
            metadata
        }
        .padding(20)
        .frame(maxWidth: 720)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 30, y: 12)
    }

    @ViewBuilder
    private var preview: some View {
        if let nsImage = image.nsImage {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 680, maxHeight: 480)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 38, weight: .light))
                Text("Couldn't decode image")
                    .font(.system(size: 12))
            }
            .foregroundColor(palette.muted)
            .frame(width: 480, height: 240)
            .background(palette.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var metadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(image.fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    metaPill(image.dimensionsLabel)
                    metaPill(image.sizeLabel)
                    metaPill(image.mimeType.replacingOccurrences(of: "image/", with: "").uppercased())
                }
            }
            Spacer()
            Button(action: { state.dismissLightbox() }) {
                Text("Close")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.text)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.chip)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(palette.chipBorder, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundColor(palette.muted)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.surfaceInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(palette.chipBorder, lineWidth: 1)
            )
    }
}
