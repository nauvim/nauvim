use super::selection::named;
use super::*;
use crate::api::fonts::{FontRange, resolve_fonts};

use skrifa::raw::{FontRef, types::NameId};

use std::fs;

use skrifa::Tag;
use write_fonts::FontBuilder;

const DATA: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../test/fixtures/grid_test.ttf"
));

fn request() -> FontRequest {
    FontRequest {
        family: "NauvimGridTest".into(),
        subfamily: None,
        path: None,
    }
}

fn name_table(names: &[(u16, &str)]) -> Vec<u8> {
    let mut records = Vec::new();
    let mut strings = Vec::new();
    for &(id, value) in names {
        let bytes: Vec<_> = value.encode_utf16().flat_map(u16::to_be_bytes).collect();
        for value in [3, 1, 0x409, id, bytes.len() as u16, strings.len() as u16] {
            records.extend(value.to_be_bytes());
        }
        strings.extend(bytes);
    }
    let mut out = Vec::new();
    for value in [0, names.len() as u16, 6 + 12 * names.len() as u16] {
        out.extend(value.to_be_bytes());
    }
    out.extend(records);
    out.extend(strings);
    out
}

fn rewrite(tables: &[(Tag, Vec<u8>)]) -> Vec<u8> {
    let font = FontRef::new(DATA).unwrap();
    let mut builder = FontBuilder::new();
    for record in font.table_directory().table_records() {
        if !tables.iter().any(|(tag, _)| *tag == record.tag()) {
            builder.add_raw(
                record.tag(),
                font.table_data(record.tag()).unwrap().as_bytes(),
            );
        }
    }
    for (tag, data) in tables {
        builder.add_raw(*tag, data.as_slice());
    }
    builder.build()
}

fn named_font(family: &str, subfamily: &str) -> Vec<u8> {
    rewrite(&[(
        Tag::new(b"name"),
        name_table(&[
            (1, "Legacy family"),
            (2, "Legacy style"),
            (6, "NauvimGridTest-Regular"),
            (16, family),
            (17, subfamily),
        ]),
    )])
}

fn resolve_data(mut request: FontRequest, data: &[u8]) -> FontResolution {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("font.otf");
    fs::write(&path, data).unwrap();
    request.path = Some(path.to_str().unwrap().into());
    resolve_fonts(vec![request], Vec::new())
}

fn collection(first: &[u8], second: &[u8]) -> Vec<u8> {
    fn append(out: &mut Vec<u8>, mut font: Vec<u8>) {
        let base = out.len() as u32;
        let count = u16::from_be_bytes(font[4..6].try_into().unwrap()) as usize;
        for record in font[12..].as_chunks_mut::<16>().0.iter_mut().take(count) {
            let offset = u32::from_be_bytes(record[8..12].try_into().unwrap());
            record[8..12].copy_from_slice(&(offset + base).to_be_bytes());
        }
        out.extend(font);
    }
    let mut data = b"ttcf".to_vec();
    for value in [0x0001_0000u32, 2, 20, 20 + first.len() as u32] {
        data.extend(value.to_be_bytes());
    }
    append(&mut data, first.to_vec());
    append(&mut data, second.to_vec());
    data
}

#[test]
fn reads_metrics_and_coverage_of_the_exact_face() {
    let resolution = resolve_data(request(), DATA);
    assert!(resolution.diagnostics.is_empty());
    let font = resolution.fonts.into_iter().next().unwrap();
    assert_eq!(
        (
            font.info.ascent,
            font.info.descent,
            font.info.line_gap,
            font.info.advance
        ),
        (1.0, 0.0, 0.0, 1.0)
    );
    assert_eq!(
        font.info.coverage,
        [
            FontRange {
                first: 0x20,
                last: 0x20
            },
            FontRange {
                first: 0x4d,
                last: 0x4d
            },
            FontRange {
                first: 0x78,
                last: 0x78
            },
            FontRange {
                first: 0xe000,
                last: 0xe002
            },
        ]
    );
    assert_eq!(font.data, DATA);
    assert!(font.variations.is_empty());
}

#[test]
fn matches_only_typographic_names_with_exact_unicode_spelling() {
    let data = named_font("NauvimGridTest", "Medium");
    for (family, subfamily, success) in [
        ("NauvimGridTest", Some("Medium"), true),
        ("NauvimGridTest", None, true),
        ("Legacy family", None, false),
        ("NauvimGridTest", Some("Legacy style"), false),
        ("nauvimgridtest", None, false),
        ("NauvimGridTest", Some("medium"), false),
    ] {
        let result = resolve_data(
            FontRequest {
                family: family.into(),
                subfamily: subfamily.map(str::to_owned),
                path: None,
            },
            &data,
        );
        assert_eq!(
            result.fonts.len(),
            usize::from(success),
            "{family}, {subfamily:?}"
        );
    }
    let legacy_only = rewrite(&[(
        Tag::new(b"name"),
        name_table(&[(1, "NauvimGridTest"), (2, "Regular")]),
    )]);
    assert!(resolve_data(request(), &legacy_only).fonts.is_empty());
    let unicode = named_font("試験é", "Regular");
    for (family, success) in [("試験é", true), ("試験e\u{301}", false)] {
        let result = resolve_data(
            FontRequest {
                family: family.into(),
                ..request()
            },
            &unicode,
        );
        assert_eq!(result.fonts.len(), usize::from(success));
    }
}

#[test]
fn scans_explicit_collection_faces_and_exports_a_checksummed_standalone_font() {
    let first = named_font("NauvimGridTest", "Regular");
    let second = rewrite(&[
        (
            Tag::new(b"name"),
            name_table(&[(16, "NauvimGridTest"), (17, "Medium")]),
        ),
        (Tag::new(b"DSIG"), vec![0, 0, 0, 1, 0, 0, 0, 0]),
    ]);
    let data = collection(&first, &second);
    let mut wanted = request();
    wanted.subfamily = Some("Medium".into());
    let result = resolve_data(wanted, &data);
    assert!(result.diagnostics.is_empty());
    let font = result.fonts.into_iter().next().unwrap();
    let parsed = FontRef::new(&font.data).unwrap();
    assert!(named(&parsed, NameId::TYPOGRAPHIC_SUBFAMILY_NAME, "Medium"));
    assert_eq!(
        skrifa::raw::tables::compute_checksum(&font.data),
        0xb1b0_afba
    );
    assert!(!font.data.starts_with(b"ttcf"));
    assert!(parsed.table_data(Tag::new(b"DSIG")).is_none());
}

#[test]
fn preserves_candidate_order_and_font_request_indices() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("fonts.ttc");
    fs::write(
        &path,
        collection(
            &named_font("NauvimGridTest", "Regular"),
            &named_font("NauvimGridTest", "Medium"),
        ),
    )
    .unwrap();
    let path = path.to_str().unwrap();
    let result = resolve_fonts(
        vec![
            request(),
            FontRequest {
                subfamily: Some("Regular".into()),
                ..request()
            },
        ],
        vec![
            FontCandidate {
                request: 0,
                path: path.into(),
                index: 1,
                postscript_name: None,
            },
            FontCandidate {
                request: 0,
                path: path.into(),
                index: 0,
                postscript_name: None,
            },
            FontCandidate {
                request: 1,
                path: path.into(),
                index: 0,
                postscript_name: None,
            },
        ],
    );
    assert!(result.diagnostics.is_empty());
    assert_eq!(
        result
            .fonts
            .iter()
            .map(|font| font.request)
            .collect::<Vec<_>>(),
        [0, 1]
    );
    assert!(named(
        &FontRef::new(&result.fonts[0].data).unwrap(),
        NameId::TYPOGRAPHIC_SUBFAMILY_NAME,
        "Medium"
    ));
    assert!(named(
        &FontRef::new(&result.fonts[1].data).unwrap(),
        NameId::TYPOGRAPHIC_SUBFAMILY_NAME,
        "Regular"
    ));
}

fn variable_font(tag: &[u8; 4]) -> Vec<u8> {
    let mut fvar = Vec::new();
    for value in [1u16, 0, 16, 2, 1, 20, 1, 10] {
        fvar.extend(value.to_be_bytes());
    }
    fvar.extend(tag);
    for value in [100i32 << 16, 650 << 16, 900 << 16] {
        fvar.extend(value.to_be_bytes());
    }
    for value in [0u16, 256, 257, 0] {
        fvar.extend(value.to_be_bytes());
    }
    fvar.extend((900i32 << 16).to_be_bytes());
    fvar.extend(258u16.to_be_bytes());
    rewrite(&[
        (Tag::new(b"fvar"), fvar),
        (
            Tag::new(b"name"),
            name_table(&[
                (1, "Legacy"),
                (2, "Regular"),
                (6, "BasePS"),
                (16, "NauvimGridTest"),
                (17, "Medium"),
                (256, "Weight"),
                (257, "Bold"),
                (258, "NamedPS"),
            ]),
        ),
    ])
}

#[test]
fn pins_every_variable_axis_to_its_default_instead_of_a_native_named_instance() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("variable.ttf");
    let bytes = variable_font(b"wght");
    fs::write(&path, &bytes).unwrap();
    let result = resolve_fonts(
        vec![request()],
        vec![FontCandidate {
            request: 0,
            path: path.to_str().unwrap().into(),
            index: 0x0001_0000,
            postscript_name: Some("NamedPS".into()),
        }],
    );
    assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
    let font = &result.fonts[0];
    assert_eq!(font.variations.len(), 1);
    assert_eq!(
        (&font.variations[0].axis, font.variations[0].value),
        (&"wght".to_string(), 650.0)
    );
    assert_eq!(font.data, bytes);
    let result = resolve_data(
        FontRequest {
            subfamily: Some("Bold".into()),
            ..request()
        },
        &bytes,
    );
    assert!(
        result.fonts.is_empty(),
        "fvar names must not masquerade as name ID17"
    );
}

#[test]
fn rejects_non_opentype_invalid_faces_and_invalid_axis_tags() {
    for data in [b"".as_slice(), b"not an OpenType font".as_slice()] {
        assert!(resolve_data(request(), data).fonts.is_empty());
    }
    assert!(
        resolve_data(request(), &variable_font(b"wg\x01t"))
            .fonts
            .is_empty()
    );
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("font.ttf");
    fs::write(&path, DATA).unwrap();
    let result = resolve_fonts(
        vec![request()],
        vec![FontCandidate {
            request: 0,
            path: path.to_str().unwrap().into(),
            index: 1,
            postscript_name: None,
        }],
    );
    assert!(result.fonts.is_empty());
    assert_eq!(result.diagnostics.len(), 1);
}

#[test]
fn reserves_generic_names_only_for_installed_searches() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("font.ttf");
    fs::write(&path, DATA).unwrap();
    let generic = || FontRequest {
        family: "monospace".into(),
        subfamily: None,
        path: None,
    };
    let result = resolve_fonts(
        vec![generic()],
        vec![FontCandidate {
            request: 0,
            path: path.to_str().unwrap().into(),
            index: 0,
            postscript_name: None,
        }],
    );
    assert_eq!(result.fonts.len(), 1);
    assert!(resolve_data(generic(), DATA).fonts.is_empty());
}
