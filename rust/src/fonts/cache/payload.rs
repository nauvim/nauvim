use crate::api::fonts::{FontInfo, FontRange, FontVariation, ResolvedFont};

use super::{CachedFace, MAX_BYTES};

use sha2::{Digest as _, Sha256};

use std::str;

const RANGE_LEN: usize = 8;
const AXIS_LEN: usize = 12;

pub(super) struct Encoded<'a> {
    data: &'a [u8],
    metrics: [[u8; 8]; 4],
    metadata: Vec<u8>,
    coverage_len: usize,
}

impl<'a> Encoded<'a> {
    pub(super) fn new(font: &'a ResolvedFont) -> Option<Self> {
        let data = font.data.as_slice();
        let metrics = [
            font.info.ascent.to_le_bytes(),
            font.info.descent.to_le_bytes(),
            font.info.line_gap.to_le_bytes(),
            font.info.advance.to_le_bytes(),
        ];
        let coverage_len = font.info.coverage.len().checked_mul(RANGE_LEN)?;
        let variations_len = font.variations.iter().try_fold(0usize, |len, axis| {
            len.checked_add(axis.axis.len())?.checked_add(8)
        })?;
        let len = coverage_len.checked_add(variations_len)?;
        if data
            .len()
            .checked_add(metrics.as_flattened().len())?
            .checked_add(len)?
            > MAX_BYTES
        {
            return None;
        }

        let mut metadata = Vec::with_capacity(len);
        for range in &font.info.coverage {
            metadata.extend(range.first.to_le_bytes());
            metadata.extend(range.last.to_le_bytes());
        }
        for axis in &font.variations {
            metadata.extend_from_slice(axis.axis.as_bytes());
            metadata.extend(axis.value.to_le_bytes());
        }
        Some(Self {
            data,
            metrics,
            metadata,
            coverage_len,
        })
    }

    pub(super) fn columns(&self) -> [&[u8]; 4] {
        // Encoding appends RANGE_LEN bytes per range before any variations.
        let (coverage, variations) = self.metadata.split_at(self.coverage_len);
        [self.data, self.metrics.as_flattened(), coverage, variations]
    }
}

impl CachedFace {
    pub(super) fn decode(columns: [&[u8]; 4], digest: &[u8], source: &[u8]) -> Option<Self> {
        if digest.len() != 32
            || payload_size(&columns)? > MAX_BYTES
            || checksum(&columns).as_slice() != digest
        {
            return None;
        }

        let [data, metrics, coverage, variations] = columns;
        let (metrics, tail) = metrics.as_chunks::<8>();
        let [ascent, descent, line_gap, advance] = metrics else {
            return None;
        };
        let [ascent, descent, line_gap, advance] =
            [ascent, descent, line_gap, advance].map(|bytes| f64::from_le_bytes(*bytes));
        let height = ascent + descent;
        if !tail.is_empty()
            || ![ascent, descent, line_gap, advance, height]
                .into_iter()
                .all(f64::is_finite)
            || ascent < 0.0
            || descent < 0.0
            || line_gap < 0.0
            || advance <= 0.0
            || height <= 0.0
        {
            return None;
        }

        let (ranges, tail) = coverage.as_chunks::<RANGE_LEN>();
        if !tail.is_empty() {
            return None;
        }
        let mut coverage: Vec<FontRange> = Vec::with_capacity(ranges.len());
        for range in ranges {
            let (first, last) = range.split_first_chunk::<4>()?;
            let first = u32::from_le_bytes(*first);
            let last = u32::from_le_bytes(last.try_into().ok()?);
            if first > last
                || last > 0x10ffff
                || coverage
                    .last()
                    .is_some_and(|previous| previous.last >= first)
            {
                return None;
            }
            coverage.push(FontRange { first, last });
        }

        let (axes, tail) = variations.as_chunks::<AXIS_LEN>();
        if !tail.is_empty() {
            return None;
        }
        let mut variations = Vec::with_capacity(axes.len());
        for axis in axes {
            let (tag, value) = axis.split_first_chunk::<4>()?;
            let value = f64::from_le_bytes(value.try_into().ok()?);
            if !value.is_finite() || !tag.iter().all(|byte| (b' '..=b'~').contains(byte)) {
                return None;
            }
            variations.push(FontVariation {
                axis: str::from_utf8(tag).ok()?.to_owned(),
                value,
            });
        }

        Some(Self {
            replacement: (data != source).then(|| data.to_owned()),
            info: FontInfo {
                ascent,
                descent,
                line_gap,
                advance,
                coverage,
            },
            variations,
        })
    }
}

fn payload_size(columns: &[&[u8]; 4]) -> Option<usize> {
    columns
        .iter()
        .try_fold(0usize, |size, column| size.checked_add(column.len()))
}

pub(super) fn checksum(columns: &[&[u8]; 4]) -> [u8; 32] {
    let mut hash = Sha256::new();
    for column in columns {
        hash.update(column.len().to_le_bytes());
        hash.update(column);
    }
    hash.finalize().into()
}
