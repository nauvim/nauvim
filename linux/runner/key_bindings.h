#ifndef NAUVIM_KEY_BINDINGS_H_
#define NAUVIM_KEY_BINDINGS_H_

#include <gdk/gdk.h>
#include <vector>

enum class PreviewAction { none, reload, go_back, go_forward, close, focus_editor };

struct KeyBinding {
  KeyBinding(const char* name, unsigned modifiers, const char* action);
  guint key;
  unsigned modifiers;
  PreviewAction action;
};

guint nauvim_keyval(const char* name);
guint nauvim_shortcut_keyval(guint keyval, guint base, guint shifted);
unsigned nauvim_key_modifiers(guint state);
const KeyBinding* nauvim_key_binding(const std::vector<KeyBinding>& bindings,
                                    guint keyval, guint state);

#endif
