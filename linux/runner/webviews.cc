#include "webviews.h"
#include "key_bindings.h"
#include "window_options.h"
#include <webkit2/webkit2.h>
#include <fontconfig/fontconfig.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <set>
#include <string>

struct Windows {
  GtkWindow* main;
  GtkOverlay* overlay;
  FlMethodChannel* channel;
  GHashTable* views;
  bool closing;
  FlView* flutter;
  std::vector<KeyBinding> key_bindings;
  int last_width = 0;
  int last_height = 0;
};
static gboolean preview_key(GtkWidget* widget, GdkEventKey* event, gpointer data) {
  auto* windows = static_cast<Windows*>(data);
  if (windows->key_bindings.empty()) return FALSE;
  auto state = static_cast<GdkModifierType>(event->state);
  auto* keymap = gdk_keymap_get_for_display(gtk_widget_get_display(widget));
  gdk_keymap_add_virtual_modifiers(keymap, &state);
  guint base = 0, shifted = 0;
  gdk_keymap_translate_keyboard_state(keymap, event->hardware_keycode,
      static_cast<GdkModifierType>(0), event->group, &base, nullptr, nullptr, nullptr);
  gdk_keymap_translate_keyboard_state(keymap, event->hardware_keycode,
      GDK_SHIFT_MASK, event->group, &shifted, nullptr, nullptr, nullptr);
  const auto* binding = nauvim_key_binding(windows->key_bindings,
      nauvim_shortcut_keyval(event->keyval, base, shifted), state);
  if (!binding) return FALSE;
  auto* view = WEBKIT_WEB_VIEW(widget);
  if (binding->action == PreviewAction::reload) webkit_web_view_reload(view);
  else if (binding->action == PreviewAction::go_back) webkit_web_view_go_back(view);
  else if (binding->action == PreviewAction::go_forward) webkit_web_view_go_forward(view);
  else if (binding->action == PreviewAction::focus_editor) gtk_widget_grab_focus(GTK_WIDGET(windows->flutter));
  else if (binding->action == PreviewAction::close) {
    auto* handle = static_cast<gint64*>(g_object_get_data(G_OBJECT(widget), "nauvim-handle"));
    if (handle) {
      g_autoptr(FlValue) args = fl_value_new_int(*handle);
      fl_method_channel_invoke_method(windows->channel, "close_webview_requested", args,
                                     nullptr, nullptr, nullptr);
    }
    gtk_widget_grab_focus(GTK_WIDGET(windows->flutter));
  } else return FALSE;
  return TRUE;
}
static FlValue* webview_args(WebKitWebView* view) {
  auto* handle = static_cast<gint64*>(g_object_get_data(G_OBJECT(view), "nauvim-handle"));
  FlValue* args = fl_value_new_map();
  fl_value_set_string_take(args, "handle", fl_value_new_int(*handle));
  return args;
}
static void report_error(WebKitWebView* view, Windows* windows, const char* message) {
  g_autoptr(FlValue) args = webview_args(view);
  fl_value_set_string_take(args, "message", fl_value_new_string(message));
  fl_method_channel_invoke_method(windows->channel, "webview_error", args,
                                 nullptr, nullptr, nullptr);
}
static gboolean load_failed(WebKitWebView* view, WebKitLoadEvent, gchar* uri,
                            GError* error, gpointer data) {
  if (g_error_matches(error, WEBKIT_NETWORK_ERROR, WEBKIT_NETWORK_ERROR_CANCELLED) ||
      g_error_matches(error, WEBKIT_POLICY_ERROR, WEBKIT_POLICY_ERROR_FRAME_LOAD_INTERRUPTED_BY_POLICY_CHANGE))
    return FALSE;
  g_autofree gchar* message = g_strdup_printf("Open preview %s: %s", uri, error->message);
  report_error(view, static_cast<Windows*>(data), message);
  return FALSE;
}
static void process_terminated(WebKitWebView* view, WebKitWebProcessTerminationReason,
                               gpointer data) {
  report_error(view, static_cast<Windows*>(data), "The preview web process terminated");
}
struct NavigationDecision {
  WebKitPolicyDecision* decision;
  GCancellable* lifetime;
};
static void navigation_checked(GObject* source, GAsyncResult* result, gpointer data) {
  auto* pending = static_cast<NavigationDecision*>(data);
  g_autoptr(FlMethodResponse) response =
      fl_method_channel_invoke_method_finish(FL_METHOD_CHANNEL(source), result, nullptr);
  FlValue* allowed = FL_IS_METHOD_SUCCESS_RESPONSE(response)
      ? fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response))
      : nullptr;
  if (!g_cancellable_is_cancelled(pending->lifetime) && allowed &&
      fl_value_get_type(allowed) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(allowed)) {
    webkit_policy_decision_use(pending->decision);
  } else {
    webkit_policy_decision_ignore(pending->decision);
  }
  g_object_unref(pending->lifetime);
  g_object_unref(pending->decision);
  delete pending;
}
static gboolean decide_policy(WebKitWebView* view, WebKitPolicyDecision* decision,
                              WebKitPolicyDecisionType type, gpointer data) {
  if (type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE) return FALSE;
  if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    webkit_policy_decision_ignore(decision);
    return TRUE;
  }
  auto* windows = static_cast<Windows*>(data);
  auto* lifetime = G_CANCELLABLE(g_object_get_data(G_OBJECT(view), "nauvim-lifetime"));
  auto* action = webkit_navigation_policy_decision_get_navigation_action(
      WEBKIT_NAVIGATION_POLICY_DECISION(decision));
  const char* uri = webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
  if (!uri || g_cancellable_is_cancelled(lifetime)) {
    webkit_policy_decision_ignore(decision);
    return TRUE;
  }
  // WebKitGTK's request-time policy does not identify the target frame.
  // Check every frame navigation so unnamed targets and redirects are covered.
  g_autoptr(FlValue) args = webview_args(view);
  fl_value_set_string_take(args, "url", fl_value_new_string(uri));
  auto* pending = new NavigationDecision {g_object_ref(decision), g_object_ref(lifetime)};
  fl_method_channel_invoke_method(windows->channel, "webview_allows_navigation", args,
                                 lifetime, navigation_checked, pending);
  return TRUE;
}
static void cancel_navigation(GtkWidget*, gpointer data) {
  g_cancellable_cancel(G_CANCELLABLE(data));
}
// Native APIs supply candidates, not final family-name matching. Rust checks
// OpenType typographic names and loads the exact selected face into Flutter.
static FlValue* font_candidates(FlValue* args) {
  FlValue* result = fl_value_new_list();
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_LIST) return result;
  for (size_t i = 0; i < fl_value_get_length(args); ++i) {
    FlValue* item = fl_value_get_list_value(args, i);
    if (fl_value_get_type(item) != FL_VALUE_TYPE_STRING) continue;
    const char* requested = fl_value_get_string(item);
    if (!*requested) continue;
    const bool generic = g_str_equal(requested, "monospace") ||
                         g_str_equal(requested, "sans-serif") ||
                         g_str_equal(requested, "serif");
    FcPattern* pattern = FcPatternCreate();
    if (!pattern) continue;
    FcPatternAddString(pattern, FC_FAMILY,
        reinterpret_cast<const FcChar8*>(fl_value_get_string(item)));
    FcPatternAddInteger(pattern, FC_WEIGHT, FC_WEIGHT_REGULAR);
    FcPatternAddInteger(pattern, FC_SLANT, FC_SLANT_ROMAN);
    FcConfigSubstitute(nullptr, pattern, FcMatchPattern);
    FcDefaultSubstitute(pattern);
    FcResult status;
    // Keep faces with duplicate coverage: a requested typographic subfamily
    // can have exactly the same character coverage as the regular face.
    FcFontSet* fonts = FcFontSort(nullptr, pattern, FcFalse, nullptr, &status);
    FcPatternDestroy(pattern);
    std::set<std::pair<std::string, uint32_t>> seen;
    for (int j = 0; fonts && j < fonts->nfont; ++j) {
      // Fontconfig stores both typographic and legacy family names. This is
      // only a candidate filter; Rust still requires name ID 16 for named fonts.
      bool family_matches = generic;
      FcChar8* family = nullptr;
      for (int k = 0; !family_matches &&
          FcPatternGetString(fonts->fonts[j], FC_FAMILY, k, &family) == FcResultMatch; ++k) {
        family_matches = g_ascii_strcasecmp(requested,
            reinterpret_cast<const char*>(family)) == 0;
      }
      if (!family_matches) continue;
      FcChar8* path = nullptr;
      int index = 0;
      if (FcPatternGetString(fonts->fonts[j], FC_FILE, 0, &path) != FcResultMatch)
        continue;
      if (!g_utf8_validate(reinterpret_cast<const char*>(path), -1, nullptr)) continue;
      FcPatternGetInteger(fonts->fonts[j], FC_INDEX, 0, &index);
      const uint32_t face = static_cast<uint32_t>(index) & 0xffff;
      if (!seen.emplace(reinterpret_cast<const char*>(path), face).second) continue;
      FlValue* font = fl_value_new_map();
      fl_value_set_string_take(font, "request", fl_value_new_int(i));
      fl_value_set_string_take(font, "path", fl_value_new_string(reinterpret_cast<const char*>(path)));
      fl_value_set_string_take(font, "index", fl_value_new_int(face));
      fl_value_append_take(result, font);
      if (generic) break;
    }
    if (fonts) FcFontSetDestroy(fonts);
  }
  return result;
}
static FlValue* value(FlValue* args, const char* name) {
  return args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(args, name) : nullptr;
}
static double number(FlValue* args, const char* name) {
  FlValue* v = value(args, name);
  if (!v) return 0;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return static_cast<double>(fl_value_get_int(v));
  return 0;
}
static int dimension(FlValue* args, const char* name) {
  const double v = number(args, name);
  if (!std::isfinite(v)) return 0;
  return static_cast<int>(std::min(static_cast<double>(G_MAXINT), std::max(0., v)));
}
static gint64 integer(FlValue* args, const char* name) {
  FlValue* v = value(args, name);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_INT ? fl_value_get_int(v) : 0;
}
static bool boolean(FlValue* args, const char* name) {
  FlValue* v = value(args, name);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(v);
}
static const char* string(FlValue* args, const char* name) {
  FlValue* v = value(args, name);
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING ? fl_value_get_string(v) : "";
}
// GTK geometry hints use integer logical pixels. At HiDPI a cell can occupy
// half a logical pixel; use a small integral group of cells in that case.
static int grid_increment(double cell) {
  for (int n = 1; n <= 64; ++n) {
    const double size = cell * n;
    if (std::abs(size - std::round(size)) < 1e-6)
      return std::max(1, static_cast<int>(std::round(size)));
  }
  return std::max(1, static_cast<int>(std::round(cell)));
}
static void configure_window(Windows* windows, FlValue* args) {
  WindowOptions options;
  options.width = dimension(args, "width");
  options.height = dimension(args, "height");
  options.decorated = !g_str_equal(string(args, "decorations"), "none");
  if (value(args, "opacity")) options.opacity = number(args, "opacity");
  if (g_str_equal(string(args, "startup_mode"), "maximized"))
    options.mode = WindowMode::maximized;
  else if (g_str_equal(string(args, "startup_mode"), "fullscreen"))
    options.mode = WindowMode::fullscreen;
  nauvim_configure_window(windows->main, options);
}
static void configure_grid(Windows* windows, FlValue* args) {
  const double cw = number(args, "cell_width");
  const double ch = number(args, "cell_height");
  if (!std::isfinite(cw) || !std::isfinite(ch) || cw <= 0 || ch <= 0 || cw > 4096 || ch > 4096)
    return;
  GdkGeometry geometry = {};
  geometry.width_inc = grid_increment(cw);
  geometry.height_inc = grid_increment(ch);
  geometry.base_width = std::min(dimension(args, "base_width"), G_MAXINT - geometry.width_inc);
  const int min_rows = std::max(1, dimension(args, "min_rows"));
  const double min_grid_height = std::ceil(min_rows * ch / geometry.height_inc) * geometry.height_inc;
  const int min_height = static_cast<int>(std::min(static_cast<double>(G_MAXINT), min_grid_height));
  geometry.base_height = std::min(dimension(args, "base_height"), G_MAXINT - min_height);
  geometry.min_width = geometry.base_width + geometry.width_inc;
  geometry.min_height = geometry.base_height + min_height;
  gtk_window_set_geometry_hints(windows->main, nullptr, &geometry,
      static_cast<GdkWindowHints>(GDK_HINT_BASE_SIZE | GDK_HINT_MIN_SIZE | GDK_HINT_RESIZE_INC));
  GdkWindow* window = gtk_widget_get_window(GTK_WIDGET(windows->main));
  if (nauvim_window_mode_pending(windows->main) || !window || (gdk_window_get_state(window) &
      (GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN | GDK_WINDOW_STATE_TILED))) return;
  int width, height;
  gtk_window_get_size(windows->main, &width, &height);
  const int snapped_width = geometry.base_width +
      std::max(1, (width - geometry.base_width) / geometry.width_inc) * geometry.width_inc;
  const int snapped_height = std::max(geometry.min_height, geometry.base_height +
      std::max(1, (height - geometry.base_height) / geometry.height_inc) * geometry.height_inc);
  if (width != snapped_width || height != snapped_height)
    gtk_window_resize(windows->main, snapped_width, snapped_height);
}
static gboolean certificate(WebKitWebView* view, const gchar* uri, GTlsCertificate* cert, GTlsCertificateFlags errors, gpointer) {
  if ((errors & ~G_TLS_CERTIFICATE_UNKNOWN_CA) != 0) return FALSE;
  g_autoptr(GUri) parsed = g_uri_parse(uri, G_URI_FLAGS_NONE, nullptr);
  const gchar* host = parsed ? g_uri_get_host(parsed) : nullptr;
  if (!host) return FALSE;
  webkit_web_context_allow_tls_certificate_for_host(webkit_web_view_get_context(view), cert, host);
  webkit_web_view_load_uri(view, uri);
  return TRUE;
}
static bool preview_has_focus(Windows* windows, GtkWidget* view) {
  GtkWidget* focused = gtk_window_get_focus(windows->main);
  return focused && (focused == view || gtk_widget_is_ancestor(focused, view));
}
static void set_window_focus(GtkWindow* window, GtkWidget* focus, gpointer) {
  if (!focus) return;
  GtkWidget* view = gtk_widget_get_ancestor(focus, WEBKIT_TYPE_WEB_VIEW);
  if (view && (!gtk_widget_get_can_focus(view) || !gtk_widget_get_visible(view)))
    g_signal_stop_emission_by_name(window, "set-focus");
}
static void call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* windows = static_cast<Windows*>(data);
  const char* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (g_str_equal(name, "configure_window")) {
    configure_window(windows, args);
  } else if (g_str_equal(name, "configure_grid")) {
    configure_grid(windows, args);
  } else if (g_str_equal(name, "font_candidates")) {
    g_autoptr(FlValue) fonts = font_candidates(args);
    fl_method_call_respond_success(call, fonts, nullptr);
    return;
  } else if (g_str_equal(name, "close")) {
    windows->closing = true;
    // Match Flutter's native exit path: detach the application windows before
    // quitting. Forcing widget destruction here races the raster thread.
    g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, [](gpointer window) -> gboolean {
      GtkWindow* main = GTK_WINDOW(window);
      GtkApplication* application = gtk_window_get_application(main);
      gtk_widget_hide(GTK_WIDGET(main));
      gtk_window_set_application(main, nullptr);
      g_application_quit(G_APPLICATION(application));
      return G_SOURCE_REMOVE;
    }, g_object_ref(windows->main), g_object_unref);
  } else if (g_str_equal(name, "title")) {
    gtk_window_set_title(windows->main, string(args, "title"));
  } else if (g_str_equal(name, "open_webview")) {
    windows->key_bindings.clear();
    FlValue* bindings = value(args, "key_bindings");
    if (bindings && fl_value_get_type(bindings) == FL_VALUE_TYPE_LIST) {
      for (size_t i = 0; i < fl_value_get_length(bindings); ++i) {
        FlValue* binding = fl_value_get_list_value(bindings, i);
        windows->key_bindings.push_back({string(binding, "key"),
            static_cast<unsigned>(integer(binding, "modifiers")), string(binding, "action")});
      }
    }
    gint64 handle = integer(args, "handle");
    GtkWidget* view = GTK_WIDGET(g_hash_table_lookup(windows->views, &handle));
    if (!view) {
      view = webkit_web_view_new();
      gint64* key = g_new(gint64, 1); *key = handle;
      g_hash_table_insert(windows->views, key, view);
      g_object_set_data(G_OBJECT(view), "nauvim-handle", key);
      GCancellable* lifetime = g_cancellable_new();
      g_object_set_data_full(G_OBJECT(view), "nauvim-lifetime", lifetime, g_object_unref);
      g_signal_connect(view, "destroy", G_CALLBACK(cancel_navigation), lifetime);
      gtk_widget_set_can_focus(view, boolean(args, "focusable"));
      g_signal_connect(view, "key-press-event", G_CALLBACK(preview_key), windows);
      gtk_widget_set_halign(view, GTK_ALIGN_START);
      gtk_widget_set_valign(view, GTK_ALIGN_START);
      gtk_overlay_add_overlay(windows->overlay, view);
      g_signal_connect(view, "load-failed-with-tls-errors", G_CALLBACK(certificate), nullptr);
      g_signal_connect(view, "load-failed", G_CALLBACK(load_failed), windows);
      g_signal_connect(view, "web-process-terminated", G_CALLBACK(process_terminated), windows);
      g_signal_connect(view, "decide-policy", G_CALLBACK(decide_policy), windows);
      webkit_web_view_load_uri(WEBKIT_WEB_VIEW(view), string(args, "url"));
    }
    gtk_widget_set_margin_start(view, dimension(args, "x"));
    gtk_widget_set_margin_top(view, dimension(args, "y"));
    gtk_widget_set_size_request(view, dimension(args, "width"), dimension(args, "height"));
    gtk_widget_show(view);
  } else if (g_str_equal(name, "focus_webview")) {
    gint64 handle = integer(args, "handle");
    GtkWidget* view = GTK_WIDGET(g_hash_table_lookup(windows->views, &handle));
    const bool focusable = view && gtk_widget_get_visible(view) && gtk_widget_get_can_focus(view);
    if (focusable) gtk_widget_grab_focus(view);
    if (!focusable || !preview_has_focus(windows, view)) {
      g_autoptr(FlMethodErrorResponse) response =
          fl_method_error_response_new("preview_focus", "The preview cannot receive focus", nullptr);
      fl_method_call_respond(call, FL_METHOD_RESPONSE(response), nullptr);
      return;
    }
  } else if (g_str_equal(name, "hide_webview") || g_str_equal(name, "close_webview")) {
    gint64 handle = integer(args, "handle");
    GtkWidget* view = GTK_WIDGET(g_hash_table_lookup(windows->views, &handle));
    if (view) {
      if (preview_has_focus(windows, view))
        gtk_widget_grab_focus(GTK_WIDGET(windows->flutter));
      if (g_str_equal(name, "hide_webview")) {
        gtk_widget_hide(view);
      } else {
        auto* lifetime = G_CANCELLABLE(g_object_get_data(G_OBJECT(view), "nauvim-lifetime"));
        g_cancellable_cancel(lifetime);
        g_signal_handlers_disconnect_by_data(view, windows);
        webkit_web_view_stop_loading(WEBKIT_WEB_VIEW(view));
        gtk_widget_destroy(view);
        g_hash_table_remove(windows->views, &handle);
      }
    }
  } else {
    fl_method_call_respond_not_implemented(call, nullptr); return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}
static void report_window_size(Windows* windows) {
  if (windows->closing || !gtk_widget_get_mapped(GTK_WIDGET(windows->main))) return;
  GtkWidget* view = GTK_WIDGET(windows->flutter);
  const int width = gtk_widget_get_allocated_width(view);
  const int height = gtk_widget_get_allocated_height(view);
  if (width <= 0 || height <= 0) return;
  if (width == windows->last_width && height == windows->last_height) return;
  windows->last_width = width;
  windows->last_height = height;
  g_autoptr(FlValue) size = fl_value_new_list();
  fl_value_append_take(size, fl_value_new_int(width));
  fl_value_append_take(size, fl_value_new_int(height));
  fl_method_channel_invoke_method(windows->channel, "window_size_changed", size,
                                 nullptr, nullptr, nullptr);
}
static void window_allocated(GtkWidget*, GtkAllocation*, gpointer data) {
  report_window_size(static_cast<Windows*>(data));
}
static void main_mapped(GtkWidget*, gpointer data) {
  report_window_size(static_cast<Windows*>(data));
}
static gboolean closing(GtkWidget*, GdkEvent*, gpointer data) {
  auto* windows = static_cast<Windows*>(data);
  if (windows->closing) return TRUE;
  fl_method_channel_invoke_method(windows->channel, "close_requested", nullptr, nullptr, nullptr, nullptr);
  return TRUE;
}
static void destroy(gpointer data) {
  auto* windows = static_cast<Windows*>(data);
  g_hash_table_unref(windows->views);
  g_object_unref(windows->channel);
  delete windows;
}
void nauvim_register_windows(FlView* view, GtkWindow* window, GtkOverlay* overlay) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.nauvim/window", FL_METHOD_CODEC(codec));
  auto* windows = new Windows { window, overlay, channel,
      g_hash_table_new_full(g_int64_hash, g_int64_equal, g_free, nullptr), false, view, {} };
  fl_method_channel_set_method_call_handler(channel, call, windows, nullptr);
  g_signal_connect_after(window, "size-allocate", G_CALLBACK(window_allocated), windows);
  g_signal_connect_after(window, "map", G_CALLBACK(main_mapped), windows);
  g_signal_connect(window, "set-focus", G_CALLBACK(set_window_focus), nullptr);
  g_signal_connect(window, "delete-event", G_CALLBACK(closing), windows);
  g_object_set_data_full(G_OBJECT(window), "nauvim-windows", windows, destroy);
}
