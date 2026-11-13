# ADR 0002: Pictures are found from pixel bands, not from OCR output

- Status: accepted
- Date: 2026-11-13
- Evidence: measurements on the four sample sets (clean pages),
  geometry only.

## Context

Vision reports text inside illustrations as ordinary lines. With headings
detected by line height, lettering on posters, diagrams and the cover became
headings and split the document into bogus chapters. Vision gives no "this is a
picture" signal, so picture regions have to be found some other way.

## Options considered

1. **Density**: rows where a large share of pixels is not background. Missed
   a picture drawn on a white ground: its ground is only slightly lighter
   than the page (255 against 248), and most rows held little "ink".
2. **Gaps in OCR coverage**: large areas with no text lines. Fails exactly
   where it matters, on pictures that contain text.
3. **Row bands** (chosen): consecutive rows with any non-background pixel.
   Text lines are always separated by blank rows; a picture is one tall
   unbroken band. A band is rejected only when recognized text lines account
   for at least 70% of its ink.

## Decision

- Use row bands with a small background tolerance (12 over three channels),
  so that a white ground counts as part of the picture.
- Minimum picture height is 5% of the page height.
- The detector is pure code over a `PageBitmap` value in `LayoutAnalysis`;
  image decoding and cropping live in `Conversion` behind the
  `PictureExtractor` protocol.
- Captions are attached by label or by the extra space that follows them.
  On the samples a caption is followed by a step of 3.6-3.9 line steps (one
  document) or carries a `Мал. N` label (another); paragraph gaps are 1.7-2.1.

Two OCR quirks surfaced while measuring and are handled in `LayoutAnalyzer`:

- A body line is sometimes reported with a box two or three lines high.
  Such a box overlaps its neighbours; a tall line that overlaps a line above
  or below by more than 10% of its height is not a heading.
- One visual line is sometimes reported as pieces side by side. Pieces on
  one row are joined before paragraphs are built.

## Consequences

- No dependency on Vision for pictures; the detector is unit-tested on
  synthetic bitmaps.
- Each page image is decoded twice (once by Vision, once for pixels). On a
  380-page document the whole conversion still takes about 100 seconds.
- Layouts with text beside a picture, and paper scans with noise in the
  margins, will need more than row bands (column bands, denoising).
- Running several conversions at once made one Vision request hang;
  conversions should run one at a time.
