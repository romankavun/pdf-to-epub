import DocumentModel

/// Reasons a document cannot be exported. Each one points at a defect in the
/// document model that the user can fix in the review UI.
public enum EPUBExportError: Error, Equatable, Sendable {
    /// EPUB needs at least one content document.
    case noChapters
    /// Text refers to a note that is not in ``Document/notes``.
    case missingNote(id: Note.ID)
    /// A figure or the cover refers to an image that is not in ``Document/images``.
    case missingImage(id: ImageResource.ID)
    /// Two images would be written to the same path inside the EPUB.
    case duplicateImageFilename(String)
}
