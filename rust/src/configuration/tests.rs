use super::*;

use nauvim_core::{Config, HostInfo, ProjectDirs};

fn px(value: u32) -> DisplayLength {
    DisplayLength {
        value: f64::from(value),
        unit: DisplayLengthUnit::Px,
    }
}

fn em(value: f64) -> DisplayLength {
    DisplayLength {
        value,
        unit: DisplayLengthUnit::Em,
    }
}

fn info(path: &Path) -> HostInfo {
    HostInfo {
        host_name: "ui-options-test".into(),
        user: "ui-options-test".into(),
        config_file: Some(path.to_path_buf()),
        home_dir: "/tmp".into(),
        project_dirs: ProjectDirs {
            cache_dir: "/tmp/nauvim-ui-options/cache".into(),
            data_dir: "/tmp/nauvim-ui-options/data".into(),
            runtime_dir: "/tmp/nauvim-ui-options/runtime".into(),
        },
    }
}

fn parse(options: &str) -> Result<UiOptions, Error> {
    let info = info(Path::new("/tmp/nauvim-ui-options/init.lua"));
    Config::evaluate(
        &format!("return {{ui_opts={{['{UI_ID}']={options}}}}}"),
        info,
        UI_ID,
        UiOptions::parse,
    )
    .map(|(_, options)| options)
}

#[test]
fn accepts_font_forms_and_retains_order_and_exact_names() {
    let none = parse("{}").unwrap();
    assert!(none.fonts.is_empty());
    assert!(none.window.is_none());
    let font = parse("{fonts='Typographic Family'}").unwrap();
    assert_eq!(font.fonts.len(), 1);
    assert_eq!(font.fonts[0].family, "Typographic Family");
    assert_eq!(font.fonts[0].size, 15.0);
    assert_eq!(font.fonts[0].subfamily, None);
    assert_eq!(font.fonts[0].path, None);
    let single =
        parse("{fonts={family='First',subfamily='Book',size=18,path='fonts/face.otf'}}").unwrap();
    assert_eq!(single.fonts.len(), 1);
    assert_eq!(single.fonts[0].subfamily.as_deref(), Some("Book"));
    assert_eq!(single.fonts[0].path.as_deref(), Some("fonts/face.otf"));
    assert_eq!(single.fonts[0].size, 18.0);
    let list = parse("{fonts={{family='First'},{family='Second',size=24}}}").unwrap();
    assert_eq!(
        list.fonts
            .iter()
            .map(|font| font.family.as_str())
            .collect::<Vec<_>>(),
        ["First", "Second"]
    );
    assert_eq!(
        list.fonts.iter().map(|font| font.size).collect::<Vec<_>>(),
        [15.0, 24.0]
    );
    assert!(parse("{fonts={}}").unwrap().fonts.is_empty());
}

#[test]
fn validates_font_structure_and_scalar_types() {
    for options in [
        "{fonts=true}",
        "{fonts={family='First',style='Regular'}}",
        "{fonts={family='First',size=0}}",
        "{fonts={family='First',size=-1}}",
        "{fonts={family='First',size=15.5}}",
        "{fonts={family='First',size=4294967296}}",
        "{fonts={family='First',subfamily=4}}",
        "{fonts={family='First',path=''}}",
        "{fonts={family=''}}",
        "{fonts={{size=15}}}",
        "{fonts={'First'}}",
        "{fonts={[1]={family='First'},[3]={family='Third'}}}",
        "{fonts={[0]={family='First'}}}",
        "{fonts={family='First',unknown=1}}",
        "{fonts=string.char(0xff)}",
        "{fonts='First'..string.char(0)..'Family'}",
        "{unknown=true}",
    ] {
        assert!(
            parse(options).is_err(),
            "Accepted invalid UI options {options}"
        );
    }
}

#[test]
fn parses_initial_size_and_independent_nonnegative_margins() {
    let options =
        parse("{window={height=1080,width=1920,margin={top=0,bottom=10,left=20,right=30}}}")
            .unwrap();
    let window = options.window.unwrap();
    assert_eq!(
        (window.width, window.height),
        (Some(px(1920)), Some(px(1080)))
    );
    assert_eq!(
        (
            window.margin.top,
            window.margin.bottom,
            window.margin.left,
            window.margin.right
        ),
        (px(0), px(10), px(20), px(30))
    );
    let options = parse("{window={height=600}}").unwrap();
    let window = options.window.unwrap();
    assert_eq!((window.width, window.height), (None, Some(px(600))));
    assert_eq!(
        (
            window.margin.top,
            window.margin.bottom,
            window.margin.left,
            window.margin.right
        ),
        (px(0), px(0), px(0), px(0))
    );
    for options in [
        "{window=false}",
        "{window={height=0}}",
        "{window={width=-1}}",
        "{window={width=640.5}}",
        "{window={height=4294967296}}",
        "{window={margin={bottom=-1}}}",
        "{window={margin={left=1.5}}}",
        "{window={margin={unknown=1}}}",
        "{window={unknown=1}}",
    ] {
        assert!(
            parse(options).is_err(),
            "Accepted invalid UI options {options}"
        );
    }
}

#[test]
fn parses_pixel_and_cell_lengths_independently() {
    let window = parse("{window={width='1920px',height='40em',margin={top='0.5em',bottom='1em',left=8,right='8px'}}}")
        .unwrap().window.unwrap();
    assert_eq!(window.width, Some(px(1920)));
    assert_eq!(window.height, Some(em(40.0)));
    assert_eq!(
        (
            window.margin.top,
            window.margin.bottom,
            window.margin.left,
            window.margin.right
        ),
        (em(0.5), em(1.0), px(8), px(8))
    );

    for (value, expected) in [
        ("1", px(1)),
        ("'1px'", px(1)),
        ("'001px'", px(1)),
        ("'4294967295px'", px(u32::MAX)),
        ("'100em'", em(100.0)),
        ("'0.5em'", em(0.5)),
        ("'.5em'", em(0.5)),
        ("'1e2em'", em(100.0)),
    ] {
        let options = parse(&format!("{{window={{width={value}}}}}")).unwrap();
        assert_eq!(options.window.unwrap().width, Some(expected), "{value}");
    }
    for value in ["0", "'0px'", "'0em'"] {
        let options = parse(&format!("{{window={{margin={{top={value}}}}}}}")).unwrap();
        assert_eq!(options.window.unwrap().margin.top.value, 0.0, "{value}");
    }
    let options = parse("{window={width=nil,height=nil,margin={top=nil}}}")
        .unwrap()
        .window
        .unwrap();
    assert_eq!(
        (options.width, options.height, options.margin.top),
        (None, None, px(0))
    );
}

#[test]
fn rejects_malformed_units_and_nonfinite_lengths() {
    for field in [
        "width",
        "height",
        "margin.top",
        "margin.bottom",
        "margin.left",
        "margin.right",
    ] {
        for value in [
            "1.5",
            "true",
            "{}",
            "'0.5px'",
            "'1.0px'",
            "'1e2px'",
            "'4294967296px'",
            "'-1px'",
            "'-0.5em'",
            "'NaNem'",
            "'infem'",
            "'1e309em'",
            "'10pt'",
            "'10PX'",
            "'10EM'",
            "'10'",
            "''",
            "'px'",
            "'em'",
            "' 1px'",
            "'1em '",
            "'1 em'",
            "'1.2.3em'",
            "'1pxem'",
        ] {
            let window = if let Some(side) = field.strip_prefix("margin.") {
                format!("margin={{{side}={value}}}")
            } else {
                format!("{field}={value}")
            };
            let e = parse(&format!("{{window={{{window}}}}}")).err().unwrap();
            assert!(e.to_string().contains(field), "{field}={value}: {e}");
        }
    }
    for field in ["width", "height"] {
        for value in ["0", "'0px'", "'0em'", "'-0em'"] {
            assert!(
                parse(&format!("{{window={{{field}={value}}}}}")).is_err(),
                "{field}={value}"
            );
        }
    }
}

#[test]
fn parses_window_appearance_and_startup_modes() {
    for window in ["{}", "{decorations=nil,opacity=nil,startup_mode=nil}"] {
        let options = parse(&format!("{{window={window}}}"))
            .unwrap()
            .window
            .unwrap();
        assert!(options.decorations.is_none());
        assert!(options.opacity.is_none());
        assert!(options.startup_mode.is_none());
    }

    for (decorations, expected) in [("full", true), ("none", false)] {
        for mode in ["windowed", "maximized", "fullscreen"] {
            let options = parse(&format!(
                "{{window={{width=960,height=640,margin={{left=8}},decorations='{decorations}',opacity=0.75,startup_mode='{mode}'}}}}"
            )).unwrap().window.unwrap();
            assert_eq!(
                matches!(options.decorations, Some(DisplayDecorations::Full)),
                expected
            );
            assert!(options.decorations.is_some());
            assert_eq!(options.opacity, Some(0.75));
            let selected = match options.startup_mode.unwrap() {
                DisplayStartupMode::Windowed => "windowed",
                DisplayStartupMode::Maximized => "maximized",
                DisplayStartupMode::Fullscreen => "fullscreen",
            };
            assert_eq!(selected, mode);
            assert_eq!(
                (options.width, options.height, options.margin.left),
                (Some(px(960)), Some(px(640)), px(8))
            );
        }
    }
    for (value, expected) in [("0", 0.0), ("1", 1.0), ("0.0", 0.0), ("1.0", 1.0)] {
        let options = parse(&format!("{{window={{opacity={value}}}}}")).unwrap();
        assert_eq!(options.window.unwrap().opacity, Some(expected));
    }
}

#[test]
fn rejects_invalid_window_appearance_and_startup_values() {
    for (field, values) in [
        (
            "decorations",
            ["'borderless'", "'FULL'", "true", "0", "{}", "''"],
        ),
        (
            "startup_mode",
            ["'normal'", "'MAXIMIZED'", "false", "1", "{}", "''"],
        ),
        (
            "opacity",
            ["-0.01", "1.01", "0/0", "math.huge", "'0.5'", "false"],
        ),
    ] {
        for value in values {
            let e = parse(&format!("{{window={{{field}={value}}}}}"))
                .err()
                .unwrap();
            assert!(e.to_string().contains(field), "{field}={value}: {e}");
        }
    }
}

#[test]
fn invalid_window_options_follow_complete_configuration_fallback() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("init.lua");
    std::fs::write(&path, format!(
        "return {{hosts={{chosen={{}}}},ui_opts={{['{UI_ID}']={{fonts='Ignored',window={{opacity=2}}}}}}}}"
    )).unwrap();
    let (config, options) = Config::load(Some(&path), UI_ID, UiOptions::parse).unwrap();
    assert_eq!(config.hosts().count(), 0);
    assert!(options.fonts.is_empty());
    assert!(options.window.is_none());
    assert!(
        config
            .diagnostics()
            .iter()
            .any(|e| e.contains("window.opacity"))
    );
}

#[test]
fn rejects_cycles_and_non_data_values_without_recursion() {
    let info = info(Path::new("/tmp/nauvim-ui-options/init.lua"));
    for options in [
        "local fonts={}; fonts[1]=fonts; return {fonts=fonts}",
        "return {fonts=io.stdout}",
        "local opts={}; opts.window=opts; return opts",
    ] {
        let source = format!("return {{ui_opts={{['{UI_ID}']=(function() {options} end)()}}}}");
        assert!(Config::evaluate(&source, info.clone(), UI_ID, UiOptions::parse).is_err());
    }
}

#[test]
fn follows_core_ui_selection_and_default_fallback() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("init.lua");
    let source = format!(
        "return {{hosts={{chosen={{}}}},use_ui_opts='alternate',ui_opts={{['{UI_ID}']={{fonts='Ignored'}},alternate={{fonts={{family='Selected'}}}}}}}}"
    );
    let info = info(&path);
    let (config, options) = Config::evaluate(&source, info, UI_ID, UiOptions::parse).unwrap();
    assert_eq!(config.hosts().collect::<Vec<_>>(), ["chosen"]);
    assert_eq!(options.fonts[0].family, "Selected");
    std::fs::write(&path, format!("return {{hosts={{chosen={{}}}},ui_opts={{['{UI_ID}']={{fonts={{family='Bad',size=0}}}}}}}}" )).unwrap();
    let (config, options) = Config::load(Some(&path), UI_ID, UiOptions::parse).unwrap();
    assert_eq!(config.hosts().count(), 0);
    assert!(options.fonts.is_empty());
    assert!(
        config
            .diagnostics()
            .iter()
            .any(|error| error.contains("Font.size"))
    );
}

#[test]
fn resolves_relative_font_paths_against_configuration_directory() {
    let mut options = parse("{fonts={{family='Relative',path='fonts/face.ttf'},{family='Absolute',path='/tmp/absolute.ttf'}}}").unwrap();
    options
        .resolve_paths(Some(Path::new("/tmp/client-config/init.lua")))
        .unwrap();
    assert_eq!(
        options.fonts[0].path.as_deref(),
        Some("/tmp/client-config/fonts/face.ttf")
    );
    assert_eq!(options.fonts[1].path.as_deref(), Some("/tmp/absolute.ttf"));
}
