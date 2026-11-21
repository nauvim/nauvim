use crate::api::fonts::{FontCandidate, FontRequest, FontVariation};

use super::Error;

use skrifa::Tag;
use skrifa::raw::{FileRef, FontRef, TableProvider as _, model::name::Names, types::NameId};

use std::iter;
use std::ops::Range;
use std::str;

pub(super) fn parse(data: &[u8]) -> Result<FileRef<'_>, Error> {
    FileRef::new(data).map_err(|_| Error::Invalid("invalid OpenType SFNT or collection"))
}

pub(super) fn indices(file: &FileRef<'_>) -> Range<u32> {
    0..match file {
        FileRef::Font(_) => 1,
        FileRef::Collection(collection) => collection.len(),
    }
}

pub(super) fn face<'a>(file: &FileRef<'a>, index: u32) -> Result<FontRef<'a>, Error> {
    let font = match file {
        FileRef::Collection(collection) => collection.get(index).ok(),
        FileRef::Font(font) if index == 0 => Some(font.clone()),
        FileRef::Font(_) => None,
    }
    .ok_or(Error::Invalid("invalid OpenType face index or data"))?;

    validate_face(font)
}

pub(super) fn read_face(data: &[u8], index: u32) -> Result<FontRef<'_>, Error> {
    let font = FontRef::from_index(data, index)
        .map_err(|_| Error::Invalid("invalid OpenType face index or data"))?;

    validate_face(font)
}

fn validate_face(font: FontRef<'_>) -> Result<FontRef<'_>, Error> {
    if !matches!(
        font.table_directory().sfnt_version(),
        0x0001_0000 | 0x4f54_544f
    ) {
        return Err(Error::Invalid("font is not an OpenType SFNT face"));
    }
    Ok(font)
}

pub(super) fn named(names: Names<'_>, id: NameId, expected: &str) -> bool {
    names.get(id).is_some_and(|name| {
        name.iter()
            .any(|localized| localized.name().chars().eq(expected.chars()))
    })
}

pub(super) struct Matcher<'a> {
    family: Option<&'a str>,
    subfamily: Option<&'a str>,
}

impl<'a> Matcher<'a> {
    pub(super) fn explicit(request: &'a FontRequest) -> Self {
        Self {
            family: Some(request.family.as_str()),
            subfamily: request.subfamily.as_deref(),
        }
    }

    pub(super) fn installed(request: &'a FontRequest) -> Self {
        let mut names = Self::explicit(request);
        if matches!(
            request.family.as_str(),
            "monospace" | "sans-serif" | "serif"
        ) {
            names.family = None;
        }
        names
    }

    pub(super) fn matches(&self, font: &FontRef<'_>) -> bool {
        if self.family.is_none() && self.subfamily.is_none() {
            return true;
        }

        let names = Names::from_sfnt(font);
        self.family
            .is_none_or(|name| named(names, NameId::TYPOGRAPHIC_FAMILY_NAME, name))
            && self
                .subfamily
                .is_none_or(|name| named(names, NameId::TYPOGRAPHIC_SUBFAMILY_NAME, name))
    }
}

pub(super) fn candidate_face<'a>(
    data: &'a [u8],
    candidate: &FontCandidate,
) -> Result<(u32, FontRef<'a>), Error> {
    let index = candidate.index & 0xffff;
    let Some(expected) = &candidate.postscript_name else {
        return read_face(data, index).map(|font| (index, font));
    };
    let file = parse(data)?;
    for index in iter::once(index).chain(indices(&file).filter(|other| *other != index)) {
        let Ok(font) = face(&file, index) else {
            continue;
        };
        let names = Names::from_sfnt(&font);
        if named(names, NameId::POSTSCRIPT_NAME, expected) {
            return Ok((index, font));
        }
        // CoreText can return a named instance's PostScript name. It identifies
        // the parent face here; export still pins that face to axis defaults.
        if let Ok(fvar) = font.fvar()
            && let Ok(instances) = fvar.instances()
        {
            for instance in instances.iter().flatten() {
                if instance
                    .post_script_name_id
                    .is_some_and(|id| named(names, id, expected))
                {
                    return Ok((index, font));
                }
            }
        }
    }
    Err(Error::Invalid(
        "native-selected PostScript face is absent from the file",
    ))
}

pub(super) fn variations(font: &FontRef<'_>) -> Result<Vec<FontVariation>, Error> {
    let fvar = match font.fvar() {
        Ok(fvar) => fvar,
        Err(_) if font.table_data(Tag::new(b"fvar")).is_some() => {
            return Err(Error::Invalid("invalid fvar table"));
        }
        Err(_) => return Ok(Vec::new()),
    };
    let axes = fvar
        .axes()
        .map_err(|_| Error::Invalid("invalid fvar axes"))?;
    let mut variations = Vec::with_capacity(axes.len());
    for axis in axes {
        let tag = axis.axis_tag();
        let default = axis.default_value();
        if tag.validate().is_err() || axis.min_value() > default || default > axis.max_value() {
            return Err(Error::Invalid("invalid fvar axis tag or default value"));
        }
        let tag = tag.to_be_bytes();
        let axis = str::from_utf8(&tag).map_err(|_| Error::Invalid("invalid fvar axis tag"))?;
        variations.push(FontVariation {
            axis: axis.to_owned(),
            value: default.to_f64(),
        });
    }
    Ok(variations)
}
