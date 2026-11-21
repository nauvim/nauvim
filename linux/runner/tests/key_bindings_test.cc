#include "key_bindings.h"
#include <gdk/gdkkeysyms.h>
#include <glib.h>

static void logical_keys() {
  const struct { const char* name; guint value; } cases[] = {
    {"escape", GDK_KEY_Escape}, {"enter", GDK_KEY_Return},
    {"numpadenter", GDK_KEY_KP_Enter}, {"tab", GDK_KEY_Tab},
    {"arrowleft", GDK_KEY_Left}, {"f1", GDK_KEY_F1}, {"f24", GDK_KEY_F24},
    {"c", GDK_KEY_c}, {"+", GDK_KEY_plus}, {" ", GDK_KEY_space},
    {"Ж", gdk_unicode_to_keyval(0x0436)}, {"é", gdk_unicode_to_keyval(0x00e9)},
    {"ß", gdk_unicode_to_keyval(0x00df)},
  };
  for (const auto& item : cases)
    g_assert_cmpuint(nauvim_keyval(item.name), ==, item.value);
  for (const auto* name : {"", "f0", "f25", "unknown"})
    g_assert_cmpuint(nauvim_keyval(name), ==, 0);
  g_assert_cmpuint(nauvim_shortcut_keyval(GDK_KEY_exclam, GDK_KEY_1, GDK_KEY_exclam), ==, GDK_KEY_1);
  g_assert_cmpuint(nauvim_shortcut_keyval(GDK_KEY_ampersand, GDK_KEY_ampersand, GDK_KEY_1), ==, GDK_KEY_1);
  g_assert_cmpuint(nauvim_shortcut_keyval(GDK_KEY_plus, GDK_KEY_equal, GDK_KEY_plus), ==, GDK_KEY_plus);
}

static void exact_modifiers() {
  const std::vector<KeyBinding> bindings = {{"r", 3, "reload"}, {"escape", 0, "focusEditor"}};
  g_assert_null(nauvim_key_binding(bindings, GDK_KEY_r, GDK_CONTROL_MASK));
  g_assert_null(nauvim_key_binding(bindings, GDK_KEY_r, GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_MOD1_MASK));
  const auto* binding = nauvim_key_binding(bindings, GDK_KEY_R, GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_LOCK_MASK | GDK_MOD2_MASK);
  g_assert_nonnull(binding);
  g_assert_true(binding->action == PreviewAction::reload);
  g_assert_nonnull(nauvim_key_binding(bindings, GDK_KEY_Escape, 0));
  const std::vector<KeyBinding> unicode = {{"Ж", 2, "reload"}};
  g_assert_nonnull(nauvim_key_binding(unicode, GDK_KEY_Cyrillic_ZHE, GDK_SHIFT_MASK));
  g_assert_null(nauvim_key_binding(bindings, GDK_KEY_ISO_Left_Tab, 0));
  const std::vector<KeyBinding> tab = {{"tab", 2, "focusEditor"}};
  g_assert_nonnull(nauvim_key_binding(tab, GDK_KEY_ISO_Left_Tab, GDK_SHIFT_MASK));
  g_assert_cmpuint(nauvim_key_modifiers(GDK_SUPER_MASK), ==, 8);
  g_assert_cmpuint(nauvim_key_modifiers(GDK_META_MASK), ==, 8);
}

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/keys/logical", logical_keys);
  g_test_add_func("/keys/modifiers", exact_modifiers);
  return g_test_run();
}
