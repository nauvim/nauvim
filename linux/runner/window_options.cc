#include "window_options.h"

#include <cmath>

namespace {
constexpr char kPending[] = "nauvim-window-mode-pending";
constexpr char kTimeout[] = "nauvim-window-mode-timeout";

void cancel_pending(GtkWindow* window) {
  const guint timeout = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(window), kTimeout));
  if (timeout != 0) g_source_remove(timeout);
  g_object_set_data(G_OBJECT(window), kTimeout, nullptr);
  g_object_set_data(G_OBJECT(window), kPending, nullptr);
}

gboolean state_changed(GtkWidget* widget, GdkEventWindowState* event, gpointer) {
  if (event->new_window_state & (GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN))
    cancel_pending(GTK_WINDOW(widget));
  return FALSE;
}

void destroyed(GtkWidget* widget, gpointer) {
  cancel_pending(GTK_WINDOW(widget));
}
}  // namespace

bool nauvim_window_mode_pending(GtkWindow* window) {
  return g_object_get_data(G_OBJECT(window), kPending) != nullptr;
}

void nauvim_configure_window(GtkWindow* window, const WindowOptions& options) {
  cancel_pending(window);
  gtk_window_set_decorated(window, options.decorated);
  if (std::isfinite(options.opacity) && options.opacity >= 0 && options.opacity <= 1)
    gtk_widget_set_opacity(GTK_WIDGET(window), options.opacity);

  int width, height;
  gtk_window_get_size(window, &width, &height);
  if (options.width > 0) width = options.width;
  if (options.height > 0) height = options.height;
  gtk_window_resize(window, width, height);

  if (options.mode == WindowMode::windowed) return;

  if (!g_object_get_data(G_OBJECT(window), "nauvim-window-mode-signals")) {
    g_signal_connect(window, "window-state-event", G_CALLBACK(state_changed), nullptr);
    g_signal_connect(window, "destroy", G_CALLBACK(destroyed), nullptr);
    g_object_set_data(G_OBJECT(window), "nauvim-window-mode-signals", GINT_TO_POINTER(1));
  }
  g_object_set_data(G_OBJECT(window), kPending, GINT_TO_POINTER(1));
  // A denied request must not disable ordinary cell snapping permanently.
  const guint timeout = g_timeout_add_full(G_PRIORITY_DEFAULT, 2500, [](gpointer data) -> gboolean {
    g_object_set_data(G_OBJECT(data), kPending, nullptr);
    g_object_set_data(G_OBJECT(data), kTimeout, nullptr);
    return G_SOURCE_REMOVE;
  }, g_object_ref(window), g_object_unref);
  g_object_set_data(G_OBJECT(window), kTimeout, GUINT_TO_POINTER(timeout));

  if (options.mode == WindowMode::maximized) gtk_window_maximize(window);
  else gtk_window_fullscreen(window);
}
