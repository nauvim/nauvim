#ifndef NAUVIM_WINDOW_OPTIONS_H_
#define NAUVIM_WINDOW_OPTIONS_H_

#include <gtk/gtk.h>

enum class WindowMode { windowed, maximized, fullscreen };

struct WindowOptions {
  int width = 0;
  int height = 0;
  bool decorated = true;
  double opacity = 1.0;
  WindowMode mode = WindowMode::windowed;
};

void nauvim_configure_window(GtkWindow* window, const WindowOptions& options);
void nauvim_window_first_frame(GtkWindow* window);
bool nauvim_window_mode_pending(GtkWindow* window);

#endif
