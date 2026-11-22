/// What kind of input a document is, which decides whether its pages are
/// prepared.
///
/// Decided per document, not per page: a scanned document has pages that do not
/// look scanned on their own (a dark cover, a blank page), and those must
/// be prepared like the rest so that every page of the project is in the
/// same place and in the same state.
public enum InputProfile: Sendable, Equatable {
    /// Clean pages (a born-digital PDF or any page with a uniform background): read as is.
    case cleanPage
    /// Paper pages scanned on a flatbed: cropped, cleaned and deskewed.
    case scannedPage

    /// How many pages are looked at to decide a document's profile.
    public static let sampleSize = 9

    /// The profile of one page: a scanned page when it is a page lying on a
    /// scanner bed (``PageCrop``) whose paper is grainy rather than one
    /// exact colour.
    ///
    /// The grain tells the two apart: scanned paper measured 21-48 % of
    /// pixels a few shades off the bed colour, clean pages at most 7 %.
    public init(of bitmap: ScanBitmap) {
        guard let box = PageCrop().pageBox(in: bitmap) else {
            self = .cleanPage
            return
        }
        let grain = bitmap.grainShare(in: box, against: bitmap.borderColor)
        self = grain >= PageCrop.minimumGrain ? .scannedPage : .cleanPage
    }

    /// The profile of a document from the profiles of sampled pages: a paper
    /// scan when more than half of them are.
    public init(ofDocument pages: [InputProfile]) {
        self = pages.count(where: { $0 == .scannedPage }) * 2 > pages.count ? .scannedPage : .cleanPage
    }

    /// The indices of the pages to sample in a document of `pageCount` pages:
    /// all of them up to ``sampleSize``, otherwise that many spread evenly
    /// from the first to the last.
    public static func sampleIndices(pageCount: Int) -> [Int] {
        guard pageCount > sampleSize else { return Array(0 ..< pageCount) }
        return (0 ..< sampleSize).map { $0 * (pageCount - 1) / (sampleSize - 1) }
    }
}
