use super::Error;

use skrifa::{Tag, raw::FontRef};
use write_fonts::FontBuilder;

pub(super) fn extract(font: &FontRef<'_>) -> Result<Vec<u8>, Error> {
    let records = font.table_directory().table_records();
    // FontBuilder's directory uses 16-bit search fields and 32-bit offsets.
    // At most 4095 records keeps count*16 <=65520; the checked padded total
    // bounds every intermediate position and round4() calculation in build().
    if records.is_empty() || records.len() > 4095 {
        return Err(Error::Invalid("unsupported OpenType table count"));
    }
    let count = u32::try_from(records.len()).map_err(|_| Error::Invalid("too many tables"))?;
    let mut size = count
        .checked_mul(16)
        .and_then(|n| n.checked_add(12))
        .ok_or(Error::Invalid("OpenType table directory is too large"))?;
    let head = font
        .table_data(Tag::new(b"head"))
        .ok_or(Error::Invalid("OpenType head table is absent"))?;
    if head.len() < 54 {
        return Err(Error::Invalid("OpenType head table is truncated"));
    }
    let mut builder = FontBuilder::new();
    for record in records {
        let tag = record.tag();
        // A signature authenticating the original binary cannot authenticate
        // a standalone face whose table offsets and checksum have changed.
        if tag == *b"DSIG" {
            continue;
        }
        let table = font
            .table_data(tag)
            .ok_or(Error::Invalid("table extends beyond the font data"))?;
        let bytes = table.as_bytes();
        let length = u32::try_from(bytes.len())
            .map_err(|_| Error::Invalid("OpenType table is too large"))?;
        let padded = length
            .checked_add(3)
            .map(|n| n & !3)
            .ok_or(Error::Invalid("OpenType table is too large"))?;
        size = size
            .checked_add(padded)
            .ok_or(Error::Invalid("OpenType face exceeds 32-bit offsets"))?;
        builder.add_raw(tag, bytes);
    }
    Ok(builder.build())
}
