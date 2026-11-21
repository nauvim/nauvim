use super::super::tests::parse as options;
use super::*;

#[test]
fn normalizes_separators_capitals_and_modifier_order() {
    for (source, key, modifiers) in [
        ("j", "j", 0),
        ("J", "j", 2),
        ("Shift-j", "j", 2),
        ("SHIFT_J", "j", 2),
        ("Shift-J", "j", 2),
        ("CTRL-SHIFT-c", "c", 3),
        ("CTRL_SHIFT_C", "c", 3),
        ("ctrl-C", "c", 3),
        ("ctrl-c", "c", 1),
        (" shift _ Control - c ", "c", 3),
        ("Command-Option-Return", "enter", 12),
        ("Meta_Esc", "escape", 8),
        ("Super-Space", " ", 8),
        ("Ctrl-Plus", "+", 1),
        ("Ctrl-+", "+", 1),
        ("Alt-Minus", "-", 4),
        ("Alt_Underscore", "_", 4),
        ("-", "-", 0),
        ("_", "_", 0),
        ("+", "+", 0),
        ("ctrl-Ж", "Ж", 3),
        ("ctrl-ж", "Ж", 1),
        ("é", "É", 0),
        ("É", "É", 2),
        ("ß", "ß", 0),
        ("Shift-Tab", "tab", 2),
        ("Ctrl-F24", "f24", 1),
        ("Ctrl-Page_Down", "pagedown", 1),
        ("CTRL_ARROW_UP", "arrowup", 1),
        ("PgDn", "pagedown", 0),
        ("Down", "arrowdown", 0),
        ("NumpadEnter", "numpadenter", 0),
    ] {
        assert_eq!(chord(source).unwrap(), (key.into(), modifiers), "{source}");
    }
    for source in [
        "",
        " ",
        "Ctrl++",
        "Ctrl+Shift+c",
        "Ctrl+J",
        "Ctrl-",
        "Ctrl__",
        "Ctrl--",
        "Ctrl--j",
        "Ctrl-Shift-_",
        "Ctrl-Ctrl-j",
        "Ctrl_Control_j",
        "Shift-Shift-j",
        "Shist-c",
        "hello",
        "F0",
        "F25",
        "\0",
        "Ctrl-éé",
    ] {
        assert!(chord(source).is_err(), "{source:?}");
    }
}

#[test]
fn borrows_common_key_names_and_characters() {
    for source in [
        "j",
        "J",
        "ctrl-shift-c",
        "SHIFT_CTRL_C",
        "Ctrl-Page_Down",
        "Alt-F24",
        "Ctrl-Plus",
        "Ctrl-Minus",
        "Super-Space",
    ] {
        assert!(
            matches!(chord(source).unwrap().0, Cow::Borrowed(_)),
            "{source}"
        );
    }
}

#[test]
fn parses_context_actions_and_explicit_unbindings() {
    assert!(options("{}").unwrap().key_bindings.is_none());
    let bindings = options(
        r#"{key_bindings={
        welcome={j=false, ['Ctrl-n']='select_next', ['Esc']='back'},
        clipboard={['Ctrl-Shift-c']='copy', ['Super_v']='paste'},
        webview={['Alt-Left']='go_back', ['Alt_Right']='go_forward',
                 ['Ctrl-r']='reload', ['Esc']='focus_editor', ['Ctrl-w']='close'},
    }}"#,
    )
    .unwrap()
    .key_bindings
    .unwrap();
    assert_eq!(bindings.welcome.len(), 3);
    assert_eq!(
        bindings
            .welcome
            .iter()
            .find(|b| b.key == "j")
            .unwrap()
            .action,
        None
    );
    let next = bindings.welcome.iter().find(|b| b.key == "n").unwrap();
    assert_eq!(
        (next.modifiers, next.action),
        (1, Some(KeyAction::SelectNext))
    );
    assert_eq!(bindings.clipboard.len(), 2);
    assert_eq!(bindings.webview.len(), 5);
}

#[test]
fn rejects_unknown_actions_contexts_and_normalized_duplicates() {
    for value in [
        "true",
        "{unknown={}}",
        "{welcome=true}",
        "{welcome={[1]='quit'}}",
        "{welcome={j=true}}",
        "{welcome={j=1}}",
        "{welcome={j='copy'}}",
        "{clipboard={c='quit'}}",
        "{webview={r='paste'}}",
        "{welcome={j='nauvim.welcome.navigation.up'}}",
        "{welcome={['Ctrl-j']='select_next',['Control_j']='select_previous'}}",
        "{welcome={J='select_next',['Shift-j']='select_previous'}}",
        "{welcome={['Ctrl-J']='select_next',['Control_Shift_j']='select_previous'}}",
        "{welcome={['Ctrl-Page_Down']='select_next',['Control_PageDown']='select_previous'}}",
        "{welcome={['Esc']='back',['Escape']=false}}",
        "{welcome={['Shist-c']='quit'}}",
        "{welcome={['Ctrl+j']='quit'}}",
    ] {
        assert!(
            options(&format!("{{key_bindings={value}}}")).is_err(),
            "{value}"
        );
    }
}
