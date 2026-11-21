//! Resolves font requests and prepares selected faces for the Flutter loader.

use crate::api::fonts::{FontCandidate, FontRequest, FontResolution, ResolvedFont};

mod cache;
use cache::{Cache, Key};

mod metrics;
mod selection;
mod sfnt;
mod source;

use selection::read_face;
use source::{Candidates, Selected, explicit, installed};

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
    if requests.is_empty() {
        return FontResolution {
            fonts: Vec::new(),
            diagnostics: Vec::new(),
        };
    }

    resolve_with_storage(requests, candidates, Cache::system())
}

fn resolve_with_storage(
    requests: &[FontRequest],
    candidates: &[FontCandidate],
    cache: Result<Cache, cache::Error>,
) -> FontResolution {
    let (cache, diagnostic) = match cache {
        Ok(cache) => (Some(cache), None),
        Err(e) => (None, Some(format!("Open font cache: {e}"))),
    };
    let mut result = resolve_with_cache(requests, candidates, cache);
    if let Some(diagnostic) = diagnostic {
        result.diagnostics.push(diagnostic);
    }
    result
}

fn resolve_with_cache(
    requests: &[FontRequest],
    candidates: &[FontCandidate],
    mut cache: Option<Cache>,
) -> FontResolution {
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

    let mut candidates = Candidates::new(candidates, requests);
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
            installed(request, candidates.for_request(idx))
        };
        let selected = selected.and_then(|Selected { data, index }| {
            let Some(storage) = &mut cache else {
                return export(idx, data, index);
            };
            let key = Key::new(&data, index);
            match storage.get(&key, &data) {
                Ok(Some(font)) => return Ok(font.into_font(idx, data)),
                Ok(None) => (),
                Err(e) => {
                    result.diagnostics.push(format!("Read font cache: {e}"));
                    cache = None;
                    return export(idx, data, index);
                }
            }

            let font = export(idx, data, index)?;
            if let Err(e) = storage.put(&key, &font) {
                result.diagnostics.push(format!("Write font cache: {e}"));
                cache = None;
            }
            Ok(font)
        });
        match selected {
            Ok(font) => result.fonts.push(font),
            Err(e) => result
                .diagnostics
                .push(format!("Resolve font {:?}: {e}", request.family)),
        }
    }
    result
}

fn export(request: u32, data: Vec<u8>, index: u32) -> Result<ResolvedFont, Error> {
    let font = read_face(&data, index)?;
    let info = metrics::inspect(&font)?;
    let variations = selection::variations(&font)?;
    let data = if font.ttc_index().is_some() {
        sfnt::extract(&font)?
    } else {
        data
    };
    Ok(ResolvedFont {
        request,
        data,
        info,
        variations,
    })
}

#[cfg(test)]
mod tests;
