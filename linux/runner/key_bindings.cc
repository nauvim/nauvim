#include "key_bindings.h"
#include <gdk/gdkkeysyms.h>

std::string nauvim_key_name(guint keyval) {
  switch (keyval) {
    case GDK_KEY_Escape: return "escape";
    case GDK_KEY_Return: return "enter";
    case GDK_KEY_KP_Enter: return "numpadenter";
    case GDK_KEY_Tab: case GDK_KEY_ISO_Left_Tab: return "tab";
    case GDK_KEY_BackSpace: return "backspace";
    case GDK_KEY_Delete: return "delete";
    case GDK_KEY_Insert: return "insert";
    case GDK_KEY_Up: return "arrowup";
    case GDK_KEY_Down: return "arrowdown";
    case GDK_KEY_Left: return "arrowleft";
    case GDK_KEY_Right: return "arrowright";
    case GDK_KEY_Home: return "home";
    case GDK_KEY_End: return "end";
    case GDK_KEY_Page_Up: return "pageup";
    case GDK_KEY_Page_Down: return "pagedown";
    default: break;
  }
  if (keyval >= GDK_KEY_F1 && keyval <= GDK_KEY_F24)
    return "f" + std::to_string(keyval - GDK_KEY_F1 + 1);
  gunichar c = gdk_keyval_to_unicode(keyval);
  if (!c || g_unichar_iscntrl(c)) return "";
  char buf[6];
  const int length = g_unichar_to_utf8(c, buf);
  g_autofree gchar* upper = g_utf8_strup(buf, length);
  std::string name(upper);
  for (auto& byte : name) {
    if (byte >= 'A' && byte <= 'Z') byte += 'a' - 'A';
  }
  return name;
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
  if (bindings.empty()) return nullptr;
  const auto key = nauvim_key_name(keyval);
  const auto modifiers = nauvim_key_modifiers(state);
  for (const auto& binding : bindings) {
    if (binding.key == key && binding.modifiers == modifiers) return &binding;
  }
  return nullptr;
}
