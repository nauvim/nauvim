/// One configured font selector. Explicit paths use literal typographic names.
pub struct FontRequest {
    pub family: String,
    pub subfamily: Option<String>,
    pub path: Option<String>,
}

/// A native-discovered face, ordered by the platform's font preference.
pub struct FontCandidate {
    /// The index of the request for which this native candidate was discovered.
    pub request: u32,
    pub path: String,
    /// Collection face index; packed Fontconfig named-instance bits are ignored.
    pub index: u32,
    pub postscript_name: Option<String>,
}

/// An inclusive Unicode coverage range.
#[derive(Debug, PartialEq)]
pub struct FontRange {
    pub first: u32,
    pub last: u32,
}

/// Font metrics in em units, independent of configured size and display scale.
pub struct FontInfo {
    pub ascent: f64,
    pub descent: f64,
    pub line_gap: f64,
    pub advance: f64,
    pub coverage: Vec<FontRange>,
}

/// An OpenType variation axis pinned to its declared default value.
pub struct FontVariation {
    pub axis: String,
    pub value: f64,
}

/// A selected standalone SFNT face ready for Flutter's runtime font loader.
pub struct ResolvedFont {
    /// Original request index, including skipped requests before this face.
    pub request: u32,
    pub data: Vec<u8>,
    pub info: FontInfo,
    pub variations: Vec<FontVariation>,
}

/// Ordered usable fonts and diagnostics for font-resolution or cache failures.
pub struct FontResolution {
    pub fonts: Vec<ResolvedFont>,
    pub diagnostics: Vec<String>,
}

/// Resolves typographic names and exports the exact selected OpenType faces.
///
/// Literal names match any decoded name ID 16/17 record exactly. The reserved
/// generic selectors apply only to installed-font searches, without a path.
/// Variable fonts always use the default value of every `fvar` axis.
///
/// Successful faces preserve request order and carry their original request
/// indices. Failed selectors contribute diagnostics instead of faces. Explicit
/// paths ignore native candidates. Source files are read without modification;
/// selected collection faces become standalone SFNT buffers for Flutter.
///
/// Prepared faces persist in SQLite under the platform cache directory. Source
/// bytes and native selection are checked on every call. Cache failures add
/// diagnostics and leave source-based font preparation available.
pub fn resolve_fonts(requests: Vec<FontRequest>, candidates: Vec<FontCandidate>) -> FontResolution {
    crate::fonts::resolve(&requests, &candidates)
}
