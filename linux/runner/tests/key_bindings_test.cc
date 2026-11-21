#include "key_bindings.h"
#include <gdk/gdkkeysyms.h>
#include <glib.h>

static void logical_keys() {
  g_assert_true(nauvim_key_name(GDK_KEY_Escape) == "escape");
  g_assert_true(nauvim_key_name(GDK_KEY_Return) == "enter");
  g_assert_true(nauvim_key_name(GDK_KEY_KP_Enter) == "numpadenter");
  g_assert_true(nauvim_key_name(GDK_KEY_ISO_Left_Tab) == "tab");
  g_assert_true(nauvim_key_name(GDK_KEY_Left) == "arrowleft");
  g_assert_true(nauvim_key_name(GDK_KEY_F1) == "f1");
  g_assert_true(nauvim_key_name(GDK_KEY_F24) == "f24");
  g_assert_true(nauvim_key_name(GDK_KEY_C) == "c");
  g_assert_true(nauvim_key_name(GDK_KEY_plus) == "+");
  g_assert_true(nauvim_key_name(GDK_KEY_space) == " ");
  g_assert_true(nauvim_key_name(gdk_unicode_to_keyval(0x0416)) == "Ж");
  g_assert_true(nauvim_key_name(gdk_unicode_to_keyval(0x00e9)) == "É");
  g_assert_cmpuint(nauvim_shortcut_keyval(GDK_KEY_exclam, GDK_KEY_1, GDK_KEY_exclam), ==, GDK_KEY_1);
  g_assert_cmpuint(nauvim_shortcut_keyval(GDK_KEY_ampersand, GDK_KEY_ampersand, GDK_KEY_1), ==, GDK_KEY_1);
  g_assert_cmpuint(nauvim_shortcut_keyval(GDK_KEY_plus, GDK_KEY_equal, GDK_KEY_plus), ==, GDK_KEY_plus);
  g_assert_true(nauvim_key_name(GDK_KEY_Shift_L).empty());
}

static void exact_modifiers() {
  const std::vector<KeyBinding> bindings = {{"r", 3, "reload"}, {"escape", 0, "focusEditor"}};
  g_assert_null(nauvim_key_binding(bindings, GDK_KEY_r, GDK_CONTROL_MASK));
  g_assert_null(nauvim_key_binding(bindings, GDK_KEY_r, GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_MOD1_MASK));
  const auto* binding = nauvim_key_binding(bindings, GDK_KEY_R, GDK_CONTROL_MASK | GDK_SHIFT_MASK | GDK_LOCK_MASK | GDK_MOD2_MASK);
  g_assert_nonnull(binding);
  g_assert_true(binding->action == "reload");
  g_assert_nonnull(nauvim_key_binding(bindings, GDK_KEY_Escape, 0));
  g_assert_cmpuint(nauvim_key_modifiers(GDK_SUPER_MASK), ==, 8);
  g_assert_cmpuint(nauvim_key_modifiers(GDK_META_MASK), ==, 8);
}

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/keys/logical", logical_keys);
  g_test_add_func("/keys/modifiers", exact_modifiers);
  return g_test_run();
}
