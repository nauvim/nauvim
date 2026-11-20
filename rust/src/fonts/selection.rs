use crate::api::fonts::{FontCandidate, FontRequest, FontVariation};

use super::Error;

use skrifa::Tag;
use skrifa::raw::{FileRef, FontRef, TableProvider as _, model::name::Names, types::NameId};

use std::iter;

pub(super) fn generic(family: &str) -> bool {
    matches!(family, "monospace" | "sans-serif" | "serif")
}

pub(super) fn count(data: &[u8]) -> Result<u32, Error> {
    match FileRef::new(data).map_err(|_| Error::Invalid("invalid OpenType SFNT or collection"))? {
        FileRef::Font(_) => Ok(1),
        FileRef::Collection(collection) => Ok(collection.len()),
    }
}

pub(super) fn face(data: &[u8], index: u32) -> Result<FontRef<'_>, Error> {
    let font = FontRef::from_index(data, index)
        .map_err(|_| Error::Invalid("invalid OpenType face index or data"))?;
    if !matches!(
        font.table_directory().sfnt_version(),
        0x0001_0000 | 0x4f54_544f
    ) {
        return Err(Error::Invalid("font is not an OpenType SFNT face"));
    }
    Ok(font)
}

pub(super) fn named(font: &FontRef<'_>, id: NameId, expected: &str) -> bool {
    Names::from_sfnt(font).get(id).is_some_and(|name| {
        name.iter()
            .any(|localized| localized.name().chars().eq(expected.chars()))
    })
}

pub(super) fn matches(request: &FontRequest, font: &FontRef<'_>, generic: bool) -> bool {
    (generic || named(font, NameId::TYPOGRAPHIC_FAMILY_NAME, &request.family))
        && request
            .subfamily
            .as_ref()
            .is_none_or(|name| named(font, NameId::TYPOGRAPHIC_SUBFAMILY_NAME, name))
}

pub(super) fn candidate_face(data: &[u8], candidate: &FontCandidate) -> Result<u32, Error> {
    let index = candidate.index & 0xffff;
    let Some(expected) = &candidate.postscript_name else {
        return Ok(index);
    };
    for index in iter::once(index).chain((0..count(data)?).filter(|other| *other != index)) {
        let Ok(font) = face(data, index) else {
            continue;
        };
        if named(&font, NameId::POSTSCRIPT_NAME, expected) {
            return Ok(index);
        }
        // CoreText can return a named instance's PostScript name. It identifies
        // the parent face here; export still pins that face to axis defaults.
        if let Ok(fvar) = font.fvar()
            && let Ok(instances) = fvar.instances()
        {
            for instance in instances.iter().flatten() {
                if instance
                    .post_script_name_id
                    .is_some_and(|id| named(&font, id, expected))
                {
                    return Ok(index);
                }
            }
        }
    }
    Err(Error::Invalid(
        "native-selected PostScript face is absent from the file",
    ))
}

pub(super) fn variations(font: &FontRef<'_>) -> Result<Vec<FontVariation>, Error> {
    Ok(match font.fvar() {
        Ok(fvar) => fvar
            .axes()
            .map_err(|_| Error::Invalid("invalid fvar axes"))?
            .iter()
            .map(|axis| {
                let tag = axis.axis_tag();
                let value = axis.default_value().to_f64();
                if tag.validate().is_err()
                    || !value.is_finite()
                    || axis.min_value() > axis.default_value()
                    || axis.default_value() > axis.max_value()
                {
                    return Err(Error::Invalid("invalid fvar axis tag or default value"));
                }
                let axis = String::from_utf8(tag.to_be_bytes().into())
                    .map_err(|_| Error::Invalid("invalid fvar axis tag"))?;
                Ok(FontVariation { axis, value })
            })
            .collect::<Result<Vec<_>, _>>()?,
        Err(_) if font.table_data(Tag::new(b"fvar")).is_some() => {
            return Err(Error::Invalid("invalid fvar table"));
        }
        Err(_) => Vec::new(),
    })
}
