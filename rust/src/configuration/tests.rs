use super::*;

use nauvim_core::{Config, HostInfo, ProjectDirs};

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
    assert_eq!((window.width, window.height), (Some(1920), Some(1080)));
    assert_eq!(
        (
            window.margin.top,
            window.margin.bottom,
            window.margin.left,
            window.margin.right
        ),
        (0, 10, 20, 30)
    );
    let options = parse("{window={height=600}}").unwrap();
    let window = options.window.unwrap();
    assert_eq!((window.width, window.height), (None, Some(600)));
    assert_eq!(
        (
            window.margin.top,
            window.margin.bottom,
            window.margin.left,
            window.margin.right
        ),
        (0, 0, 0, 0)
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
