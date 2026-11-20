use crate::api::fonts::{FontInfo, FontRange};

use super::Error;

use skrifa::MetadataProvider as _;
use skrifa::instance::{LocationRef, Size};
use skrifa::raw::{FontRef, model::metrics::Metrics};

pub(super) fn inspect(font: &FontRef<'_>) -> Result<FontInfo, Error> {
    let unscaled = Metrics::from_sfnt(font, &[]);
    let metrics = unscaled.scaled_f32(1.0);
    // CoreText uses hhea; FreeType honors the font's USE_TYPO_METRICS policy.
    #[cfg(target_os = "macos")]
    let line = metrics.hhea_line().or_else(|| metrics.h_line());
    #[cfg(not(target_os = "macos"))]
    let line = metrics.h_line();
    let line = line.ok_or(Error::Invalid("horizontal line metrics are absent"))?;
    let charmap = font.charmap();
    let glyph_metrics = font.glyph_metrics(Size::unscaled(), LocationRef::default());
    let upem = f32::from(unscaled.units_per_em);
    // The primary face's digit advance defines a terminal cell. Symbol faces
    // without digits can supply M, space, or their declared average/maximum.
    let advance = ['0', 'M', ' ']
        .into_iter()
        .filter_map(|ch| charmap.map(ch))
        .filter(|id| id.to_u32() != 0)
        .filter_map(|id| glyph_metrics.advance_width(id))
        .map(|width| width / upem)
        .find(|width| width.is_finite() && *width > 0.0)
        .or_else(|| {
            metrics
                .average_char_width()
                .filter(|width| width.is_finite() && *width > 0.0)
        })
        .or_else(|| {
            metrics
                .max_h_advance()
                .filter(|width| width.is_finite() && *width > 0.0)
        })
        .ok_or(Error::Invalid("positive horizontal advance is absent"))?;
    let ascent = f64::from(line.ascender);
    let descent = -f64::from(line.descender);
    let line_gap = f64::from(line.line_gap);
    if ![ascent, descent, line_gap, f64::from(advance)]
        .into_iter()
        .all(f64::is_finite)
        || ascent < 0.0
        || descent < 0.0
        || ascent + descent <= 0.0
    {
        return Err(Error::Invalid("invalid horizontal metrics"));
    }
    let mut coverage: Vec<FontRange> = Vec::new();
    for (codepoint, glyph) in charmap.mappings() {
        if glyph.to_u32() == 0 {
            continue;
        }
        if let Some(range) = coverage.last_mut()
            && codepoint == range.last.saturating_add(1)
        {
            range.last = codepoint;
        } else {
            coverage.push(FontRange {
                first: codepoint,
                last: codepoint,
            });
        }
    }
    Ok(FontInfo {
        ascent,
        descent,
        line_gap: line_gap.max(0.0),
        advance: f64::from(advance),
        coverage,
    })
}
