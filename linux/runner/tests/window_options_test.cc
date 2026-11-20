#include "window_options.h"

#include <cmath>

namespace {
void appearance_and_dimensions() {
  GtkWindow* window = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  gtk_window_set_default_size(window, 1280, 720);
  WindowOptions options;
  options.width = 960;
  options.decorated = false;
  options.opacity = 0.75;
  nauvim_configure_window(window, options);
  int width, height;
  gtk_window_get_size(window, &width, &height);
  g_assert_cmpint(width, ==, 960);
  g_assert_cmpint(height, ==, 720);
  g_assert_false(gtk_window_get_decorated(window));
  g_assert_true(std::abs(gtk_widget_get_opacity(GTK_WIDGET(window)) - 0.75) < 0.005);
  g_assert_true(gtk_window_get_accept_focus(window));
  g_assert_false(nauvim_window_mode_pending(window));

  nauvim_configure_window(window, WindowOptions{});
  gtk_window_get_size(window, &width, &height);
  g_assert_cmpint(width, ==, 960);
  g_assert_cmpint(height, ==, 720);
  g_assert_true(gtk_window_get_decorated(window));
  g_assert_cmpfloat(gtk_widget_get_opacity(GTK_WIDGET(window)), ==, 1.0);
  gtk_widget_destroy(GTK_WIDGET(window));
}

void startup_transition() {
  const WindowMode modes[] = {WindowMode::maximized, WindowMode::fullscreen};
  for (const auto mode : modes) {
    GtkWindow* window = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
    WindowOptions options;
    options.mode = mode;
    nauvim_configure_window(window, options);
    g_assert_true(nauvim_window_mode_pending(window));

    GdkEventWindowState event = {};
    event.type = GDK_WINDOW_STATE;
    event.new_window_state = mode == WindowMode::maximized
        ? GDK_WINDOW_STATE_MAXIMIZED : GDK_WINDOW_STATE_FULLSCREEN;
    gboolean handled = FALSE;
    g_signal_emit_by_name(window, "window-state-event", &event, &handled);
    g_assert_false(nauvim_window_mode_pending(window));

    nauvim_configure_window(window, options);
    g_assert_true(nauvim_window_mode_pending(window));
    // Destroying a window also cancels the outstanding mode timeout.
    gtk_widget_destroy(GTK_WIDGET(window));
  }
}
void unconfirmed_startup_mode_expires() {
  GtkWindow* window = GTK_WINDOW(gtk_window_new(GTK_WINDOW_TOPLEVEL));
  WindowOptions options;
  options.mode = WindowMode::fullscreen;
  // Leave the window unmapped so no window manager confirms the request.
  nauvim_configure_window(window, options);
  const gint64 deadline = g_get_monotonic_time() + 5 * G_TIME_SPAN_SECOND;
  while (nauvim_window_mode_pending(window) && g_get_monotonic_time() < deadline) {
    g_main_context_iteration(nullptr, FALSE);
    g_usleep(1000);
  }
  g_assert_false(nauvim_window_mode_pending(window));
  gtk_widget_destroy(GTK_WIDGET(window));
}
}  // namespace

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  if (!gtk_init_check(&argc, &argv)) return 77;
  // Broadway warns about its missing native cursor theme. Keep errors and
  // criticals fatal, but allow backend warnings during headless validation.
  if (g_strcmp0(g_getenv("GDK_BACKEND"), "broadway") == 0)
    g_log_set_always_fatal(static_cast<GLogLevelFlags>(G_LOG_FATAL_MASK | G_LOG_LEVEL_CRITICAL));
  g_test_add_func("/window/appearance_and_dimensions", appearance_and_dimensions);
  g_test_add_func("/window/startup_transition", startup_transition);
  g_test_add_func("/window/unconfirmed_startup_mode_expires", unconfirmed_startup_mode_expires);
  return g_test_run();
}
