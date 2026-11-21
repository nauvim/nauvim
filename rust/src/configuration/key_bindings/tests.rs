use super::super::tests::parse as options;
use super::*;

#[test]
fn normalizes_chords_without_implicit_shift_or_modifier_order() {
    for (source, key, modifiers) in [
        ("j", "j", 0),
        ("J", "j", 0),
        ("Shift+j", "j", 2),
        ("CTRL+SHIFT+C", "c", 3),
        (" shift + Control + c ", "c", 3),
        ("Command+Option+Return", "enter", 12),
        ("Meta+Esc", "escape", 8),
        ("Super+Space", " ", 8),
        ("Ctrl+Plus", "+", 1),
        ("Alt+-", "-", 4),
        ("ctrl+Ж", "Ж", 1),
        ("é", "É", 0),
        ("Shift+Tab", "tab", 2),
        ("Ctrl+F24", "f24", 1),
        ("PgDn", "pagedown", 0),
        ("Down", "arrowdown", 0),
        ("NumpadEnter", "numpadenter", 0),
    ] {
        assert_eq!(chord(source).unwrap(), (key.into(), modifiers), "{source}");
    }
    for source in [
        "",
        " ",
        "+",
        "Ctrl++",
        "Ctrl+",
        "Ctrl+Ctrl+j",
        "Ctrl+Control+j",
        "Shist+c",
        "Ctrl-Shift-c",
        "hello",
        "F0",
        "F25",
        "\0",
        "Ctrl+éé",
    ] {
        assert!(chord(source).is_err(), "{source:?}");
    }
}

#[test]
fn parses_context_actions_and_explicit_unbindings() {
    assert!(options("{}").unwrap().key_bindings.is_none());
    let bindings = options(
        r#"{key_bindings={
        welcome={j=false, ['Ctrl+N']='select_next', ['Esc']='back'},
        clipboard={['Ctrl+Shift+c']='copy', ['Super+v']='paste'},
        webview={['Alt+Left']='go_back', ['Alt+Right']='go_forward',
                 ['Ctrl+r']='reload', ['Esc']='focus_editor', ['Ctrl+w']='close'},
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
        "{welcome={['Ctrl+j']='select_next',['Control+J']='select_previous'}}",
        "{welcome={['Esc']='back',['Escape']=false}}",
        "{welcome={['Shist+c']='quit'}}",
    ] {
        assert!(
            options(&format!("{{key_bindings={value}}}")).is_err(),
            "{value}"
        );
    }
}
