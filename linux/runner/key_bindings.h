#ifndef NAUVIM_KEY_BINDINGS_H_
#define NAUVIM_KEY_BINDINGS_H_

#include <gdk/gdk.h>
#include <string>
#include <vector>

struct KeyBinding {
  std::string key;
  unsigned modifiers;
  std::string action;
};

std::string nauvim_key_name(guint keyval);
guint nauvim_shortcut_keyval(guint keyval, guint base, guint shifted);
unsigned nauvim_key_modifiers(guint state);
const KeyBinding* nauvim_key_binding(const std::vector<KeyBinding>& bindings,
                                    guint keyval, guint state);

#endif
