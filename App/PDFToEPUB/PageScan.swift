import AppModel
import Corrections
import SwiftUI

/// The page image with the area of every block outlined; clicking an area
/// puts its block in focus.
struct PageScan: View {
    var page: ReviewModel.Page
    var selectedItemID: ReviewModel.Item.ID?
    var select: (ReviewModel.Item.ID) -> Void

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
        ForEach(page.items) { item in
            let isSelected = item.id == selectedItemID
            let color = item.outlineColor
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(isSelected ? 0.25 : 0.001))
                .stroke(color.opacity(isSelected ? 1 : 0.35), lineWidth: isSelected ? 2 : 1)
                .frame(width: item.box.width * size.width + 6, height: item.box.height * size.height + 6)
                .position(x: item.box.midX * size.width, y: item.box.midY * size.height)
                .onTapGesture { select(item.id) }
        }
    }
}
