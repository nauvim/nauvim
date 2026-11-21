#include "key_bindings.h"
#include <gdk/gdkkeysyms.h>

static guint normalize_keyval(guint keyval) {
  if (keyval == GDK_KEY_ISO_Left_Tab) return GDK_KEY_Tab;
  const gunichar c = gdk_keyval_to_unicode(keyval);
  if (c && !g_unichar_iscntrl(c))
    return gdk_unicode_to_keyval(g_unichar_tolower(c));
  return keyval;
}

guint nauvim_keyval(const char* name) {
  if (!name || !*name) return 0;
  static const struct { const char* name; guint value; } named[] = {
    {"escape", GDK_KEY_Escape}, {"enter", GDK_KEY_Return},
    {"numpadenter", GDK_KEY_KP_Enter}, {"tab", GDK_KEY_Tab},
    {"backspace", GDK_KEY_BackSpace}, {"delete", GDK_KEY_Delete},
    {"insert", GDK_KEY_Insert}, {"arrowup", GDK_KEY_Up},
    {"arrowdown", GDK_KEY_Down}, {"arrowleft", GDK_KEY_Left},
    {"arrowright", GDK_KEY_Right}, {"home", GDK_KEY_Home},
    {"end", GDK_KEY_End}, {"pageup", GDK_KEY_Page_Up},
    {"pagedown", GDK_KEY_Page_Down},
  };
  for (const auto& key : named) {
    if (g_str_equal(name, key.name)) return key.value;
  }
  if (*name == 'f') {
    char* end = nullptr;
    const auto n = g_ascii_strtoull(name + 1, &end, 10);
    if (end && !*end && n >= 1 && n <= 24)
      return GDK_KEY_F1 + static_cast<guint>(n) - 1;
  }
  const gunichar c = g_utf8_get_char_validated(name, -1);
  if (c == static_cast<gunichar>(-1) || c == static_cast<gunichar>(-2) ||
      !c || g_unichar_iscntrl(c) || *g_utf8_next_char(name)) return 0;
  return gdk_unicode_to_keyval(g_unichar_tolower(c));
}

KeyBinding::KeyBinding(const char* name, unsigned modifiers, const char* action)
    : key(nauvim_keyval(name)), modifiers(modifiers), action(PreviewAction::none) {
  static const struct { const char* name; PreviewAction value; } actions[] = {
    {"reload", PreviewAction::reload}, {"goBack", PreviewAction::go_back},
    {"goForward", PreviewAction::go_forward}, {"close", PreviewAction::close},
    {"focusEditor", PreviewAction::focus_editor},
  };
  for (const auto& item : actions) {
    if (g_strcmp0(action, item.name) == 0) { this->action = item.value; break; }
  }
}

guint nauvim_shortcut_keyval(guint keyval, guint base, guint shifted) {
  // Flutter retains ASCII letter/digit identities across Shift levels, while
  // punctuation uses its produced symbol. French '&'/'1' therefore names 1.
  for (const auto value : {base, shifted}) {
    if ((value >= '0' && value <= '9') ||
        (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z')) return value;
  }
  return keyval;
}

unsigned nauvim_key_modifiers(guint state) {
  return ((state & GDK_CONTROL_MASK) ? 1 : 0) |
         ((state & GDK_SHIFT_MASK) ? 2 : 0) |
         ((state & GDK_MOD1_MASK) ? 4 : 0) |
         ((state & (GDK_META_MASK | GDK_SUPER_MASK)) ? 8 : 0);
}

const KeyBinding* nauvim_key_binding(const std::vector<KeyBinding>& bindings,
                                    guint keyval, guint state) {
  const auto key = normalize_keyval(keyval);
  const auto modifiers = nauvim_key_modifiers(state);
  for (const auto& binding : bindings) {
    if (binding.key && binding.key == key && binding.modifiers == modifiers &&
        binding.action != PreviewAction::none) return &binding;
  }
  return nullptr;
}
