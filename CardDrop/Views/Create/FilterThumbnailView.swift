import SwiftUI

struct FilterThumbnailView: View {
    let thumbnail: UIImage
    let filter: PostcardFilter
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipped()
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )

            Text(filter.rawValue)
                .font(.caption2)
                .foregroundColor(isSelected ? .brandBlue : .black)
                .padding(.bottom, 4)
        }
        .onTapGesture(perform: onTap)
    }
}
