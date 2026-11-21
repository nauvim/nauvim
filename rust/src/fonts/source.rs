use crate::api::fonts::{FontCandidate, FontRequest};

use super::Error;
use super::selection::{Matcher, candidate_face, face, indices, parse};

use std::fs;
use std::path::Path;

pub(super) struct Candidates<'a> {
    remaining: &'a [FontCandidate],
    grouped: bool,
}

impl<'a> Candidates<'a> {
    pub(super) fn new(candidates: &'a [FontCandidate], requests: &[FontRequest]) -> Self {
        let multiple_searches = requests
            .iter()
            .filter(|request| request.path.is_none())
            .nth(1)
            .is_some();
        Self {
            remaining: candidates,
            grouped: multiple_searches
                && candidates.is_sorted_by_key(|candidate| candidate.request),
        }
    }

    pub(super) fn for_request(&mut self, request: u32) -> impl Iterator<Item = &'a FontCandidate> {
        let mut candidates = self.remaining;
        if self.grouped {
            // Native discovery groups candidates by request. The caller visits
            // requests in order, so only unvisited candidates need to be scanned.
            let end = candidates.partition_point(|candidate| candidate.request <= request);
            // partition_point returns a boundary within this slice.
            (candidates, self.remaining) = candidates.split_at(end);
        }
        candidates
            .iter()
            .filter(move |candidate| candidate.request == request)
    }
}

pub(super) struct Selected {
    pub(super) data: Vec<u8>,
    pub(super) index: u32,
}

fn read(path: &Path) -> Result<Vec<u8>, Error> {
    fs::read(path).map_err(|source| Error::Read {
        path: path.to_path_buf(),
        source,
    })
}

pub(super) fn explicit(request: &FontRequest, path: &Path) -> Result<Selected, Error> {
    let data = read(path)?;
    let file = parse(&data)?;
    let names = Matcher::explicit(request);
    for index in indices(&file) {
        let font = face(&file, index)?;
        if names.matches(&font) {
            return Ok(Selected { data, index });
        }
    }
    Err(Error::Invalid("no OpenType face matches name IDs 16/17"))
}

pub(super) fn installed<'a>(
    request: &FontRequest,
    candidates: impl Iterator<Item = &'a FontCandidate>,
) -> Result<Selected, Error> {
    let names = Matcher::installed(request);
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
        let selected = candidate_face(data, candidate)
            .map(|(index, font)| names.matches(&font).then_some(index));
        match selected {
            Ok(Some(index)) => {
                if let Some((_, data)) = cached.take() {
                    return Ok(Selected { data, index });
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
