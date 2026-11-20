use crate::api::fonts::{FontCandidate, FontRequest};

use super::Error;
use super::selection::{candidate_face, count, face, generic, matches};

use std::fs;
use std::path::Path;

fn read(path: &Path) -> Result<Vec<u8>, Error> {
    fs::read(path).map_err(|source| Error::Read {
        path: path.to_path_buf(),
        source,
    })
}

pub(super) fn explicit(request: &FontRequest, path: &Path) -> Result<(Vec<u8>, u32), Error> {
    let data = read(path)?;
    let count = count(&data)?;
    for index in 0..count {
        let font = face(&data, index)?;
        if matches(request, &font, false) {
            return Ok((data, index));
        }
    }
    Err(Error::Invalid("no OpenType face matches name IDs 16/17"))
}

pub(super) fn installed<'a>(
    request: &FontRequest,
    candidates: impl Iterator<Item = &'a FontCandidate>,
) -> Result<(Vec<u8>, u32), Error> {
    // Bound the file cache to one candidate file. Collection faces commonly
    // occur consecutively; unmatched installed fonts need not remain in memory.
    let mut cached: Option<(&Path, Vec<u8>)> = None;
    let mut failure = None;
    for candidate in candidates {
        let path = Path::new(&candidate.path);

        if cached.as_ref().map(|(path, _)| *path) != Some(path) {
            match read(path) {
                Ok(data) => cached = Some((path, data)),
                Err(e) => {
                    failure = Some(e);
                    continue;
                }
            }
        }
        let Some((_, data)) = &cached else { continue };
        let selected = candidate_face(data, candidate).and_then(|index| {
            let font = face(data, index)?;
            Ok(matches(request, &font, generic(&request.family)).then_some(index))
        });
        match selected {
            Ok(Some(index)) => {
                if let Some((_, data)) = cached.take() {
                    return Ok((data, index));
                }
            }
            Ok(None) => (),
            Err(e) => failure = Some(e),
        }
    }
    Err(failure.unwrap_or(Error::Invalid(
        "no installed OpenType face matches name IDs 16/17",
    )))
}
