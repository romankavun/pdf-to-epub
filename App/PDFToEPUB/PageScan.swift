import AppModel
import Corrections
import SwiftUI

/// The page image with the area of every block outlined; clicking an area
/// puts its block in focus.
struct PageScan: View {
    var page: ReviewModel.Page
    var selectedItemID: ReviewModel.Item.ID?
    var select: (ReviewModel.Item.ID) -> Void
    /// The blocks of the selected style on this page, outlined in its
    /// colour while every other outline fades; `nil` while no style is shown.
    var highlight: Highlight?

    struct Highlight {
        var outlines: ReviewModel.StyleOutlines
        var color: Color
    }

    var body: some View {
        AsyncImage(url: page.url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
                    .overlay { GeometryReader { outlines(in: $0.size) } }
            case .failure:
                ContentUnavailableView("Could not load the page image", systemImage: "photo")
            case .empty:
                ProgressView()
            @unknown default:
                EmptyView()
            }
        }
        // A new page must not show the previous page's image while loading.
        .id(page.url)
    }

    private func outlines(in size: CGSize) -> some View {
        ZStack {
            ForEach(page.items) { item in
                let isSelected = item.id == selectedItemID
                let inStyle = highlight?.outlines.itemIDs.contains(item.id) == true
                let faded = highlight != nil && !inStyle
                let color = inStyle ? highlight?.color ?? item.outlineColor : item.outlineColor
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(isSelected ? 0.25 : inStyle ? 0.15 : 0.001))
                    .stroke(
                        color.opacity(isSelected || inStyle ? 1 : faded ? 0.12 : 0.35),
                        lineWidth: isSelected || inStyle ? 2 : 1
                    )
                    .frame(width: item.box.width * size.width + 6, height: item.box.height * size.height + 6)
                    .position(x: item.box.midX * size.width, y: item.box.midY * size.height)
                    .onTapGesture { select(item.id) }
            }
            if let highlight {
                // Page furniture has no block to select.
                ForEach(Array(highlight.outlines.furniture.enumerated()), id: \.offset) { _, box in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(highlight.color.opacity(0.15))
                        .stroke(highlight.color, lineWidth: 2)
                        .frame(width: box.width * size.width + 6, height: box.height * size.height + 6)
                        .position(x: box.midX * size.width, y: box.midY * size.height)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
