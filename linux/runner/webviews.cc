#include "webviews.h"
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
};
static void report_error(Windows* windows, const char* message) {
  g_autoptr(FlValue) args = fl_value_new_string(message);
  fl_method_channel_invoke_method(windows->channel, "window_error", args,
                                 nullptr, nullptr, nullptr);
}
static gboolean load_failed(WebKitWebView*, WebKitLoadEvent, gchar* uri,
                            GError* error, gpointer data) {
  if (g_error_matches(error, WEBKIT_NETWORK_ERROR, WEBKIT_NETWORK_ERROR_CANCELLED))
    return FALSE;
  g_autofree gchar* message = g_strdup_printf("Open preview %s: %s", uri, error->message);
  report_error(static_cast<Windows*>(data), message);
  return FALSE;
}
static void process_terminated(WebKitWebView*, WebKitWebProcessTerminationReason,
                               gpointer data) {
  report_error(static_cast<Windows*>(data), "The preview web process terminated");
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
  int width, height;
  gtk_window_get_size(windows->main, &width, &height);
  if (value(args, "width")) width = std::max(1, dimension(args, "width"));
  if (value(args, "height")) height = std::max(1, dimension(args, "height"));
  gtk_window_resize(windows->main, width, height);
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
  if (!window || (gdk_window_get_state(window) &
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
    gint64 handle = integer(args, "handle");
    GtkWidget* view = GTK_WIDGET(g_hash_table_lookup(windows->views, &handle));
    if (!view) {
      view = webkit_web_view_new();
      gint64* key = g_new(gint64, 1); *key = handle;
      g_hash_table_insert(windows->views, key, view);
      gtk_widget_set_halign(view, GTK_ALIGN_START);
      gtk_widget_set_valign(view, GTK_ALIGN_START);
      gtk_overlay_add_overlay(windows->overlay, view);
      g_signal_connect(view, "load-failed-with-tls-errors", G_CALLBACK(certificate), nullptr);
      g_signal_connect(view, "load-failed", G_CALLBACK(load_failed), windows);
      g_signal_connect(view, "web-process-terminated", G_CALLBACK(process_terminated), windows);
      webkit_web_view_load_uri(WEBKIT_WEB_VIEW(view), string(args, "url"));
    }
    gtk_widget_set_margin_start(view, dimension(args, "x"));
    gtk_widget_set_margin_top(view, dimension(args, "y"));
    gtk_widget_set_size_request(view, dimension(args, "width"), dimension(args, "height"));
    gtk_widget_show(view);
  } else if (g_str_equal(name, "close_webview")) {
    gint64 handle = integer(args, "handle");
    GtkWidget* view = GTK_WIDGET(g_hash_table_lookup(windows->views, &handle));
    if (view) {
      g_signal_handlers_disconnect_by_data(view, windows);
      webkit_web_view_stop_loading(WEBKIT_WEB_VIEW(view));
      gtk_widget_destroy(view);
      g_hash_table_remove(windows->views, &handle);
    }
  } else {
    fl_method_call_respond_not_implemented(call, nullptr); return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
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
      g_hash_table_new_full(g_int64_hash, g_int64_equal, g_free, nullptr), false };
  fl_method_channel_set_method_call_handler(channel, call, windows, nullptr);
  g_signal_connect(window, "delete-event", G_CALLBACK(closing), windows);
  g_object_set_data_full(G_OBJECT(window), "nauvim-windows", windows, destroy);
}
