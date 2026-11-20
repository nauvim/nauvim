//! Resolves font requests and prepares selected faces for the Flutter loader.

use crate::api::fonts::{FontCandidate, FontRequest, FontResolution, ResolvedFont};

mod metrics;
mod selection;
mod sfnt;
mod source;

use selection::face;
use source::{explicit, installed};

use skrifa::raw::FileRef;

use std::fmt;
use std::io;
use std::path::{Path, PathBuf};

#[derive(Debug)]
enum Error {
    Read { path: PathBuf, source: io::Error },
    Invalid(&'static str),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Read { path, source } => write!(f, "Read font {}: {source}", path.display()),
            Self::Invalid(reason) => f.write_str(reason),
        }
    }
}

pub(crate) fn resolve(requests: &[FontRequest], candidates: &[FontCandidate]) -> FontResolution {
    let mut result = FontResolution {
        fonts: Vec::new(),
        diagnostics: Vec::new(),
    };

    if let Err(e) = result.fonts.try_reserve_exact(requests.len()) {
        result
            .diagnostics
            .push(format!("Allocate resolved fonts: {e}"));
        return result;
    }

    for (idx, request) in requests.iter().enumerate() {
        let Ok(idx) = u32::try_from(idx) else {
            result
                .diagnostics
                .push("Resolve fonts: too many font selectors".into());
            break;
        };
        let selected = if let Some(path) = &request.path {
            explicit(request, Path::new(path))
        } else {
            installed(
                request,
                candidates
                    .iter()
                    .filter(|candidate| candidate.request == idx),
            )
        };
        match selected.and_then(|(data, index)| export(idx, data, index)) {
            Ok(font) => result.fonts.push(font),
            Err(e) => result
                .diagnostics
                .push(format!("Resolve font {:?}: {e}", request.family)),
        }
    }
    result
}

fn export(request: u32, data: Vec<u8>, index: u32) -> Result<ResolvedFont, Error> {
    let font = face(&data, index)?;
    let info = metrics::inspect(&font)?;
    let variations = selection::variations(&font)?;
    let standalone = if matches!(FileRef::new(&data), Ok(FileRef::Collection(_))) {
        Some(sfnt::extract(&font)?)
    } else {
        None
    };
    Ok(ResolvedFont {
        request,
        data: standalone.unwrap_or(data),
        info,
        variations,
    })
}

#[cfg(test)]
mod tests;
