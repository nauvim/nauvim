#include "native_text_input.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>

namespace {
FlValue* field(FlValue* map, const char* key) {
  if (!map || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return nullptr;
  return fl_value_lookup_string(map, key);
}

double number(FlValue* value) {
  if (value) {
    if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT)
      return fl_value_get_float(value);
    if (fl_value_get_type(value) == FL_VALUE_TYPE_INT)
      return fl_value_get_int(value);
  }
  return std::numeric_limits<double>::quiet_NaN();
}

gint pixels(double value) {
  return static_cast<gint>(std::max(static_cast<double>(G_MININT),
      std::min(value, static_cast<double>(G_MAXINT))));
}

bool rectangle(FlValue* value, GdkRectangle* rect) {
  const double left = number(field(value, "left"));
  const double top = number(field(value, "top"));
  const double width = number(field(value, "width"));
  const double height = number(field(value, "height"));
  if (!std::isfinite(left) || !std::isfinite(top) ||
      !std::isfinite(width) || !std::isfinite(height) ||
      width < 0 || height < 0)
    return false;

  *rect = {pixels(std::floor(left)), pixels(std::floor(top)),
           pixels(std::max(1.0, std::ceil(width))),
           pixels(std::max(1.0, std::ceil(height)))};
  return true;
}

gint64 advance_utf16(const gchar*& cursor, gint64& index, const gchar* end) {
  while (cursor < end) {
    index += g_utf8_get_char(cursor) > 0xffff ? 2 : 1;
    cursor = g_utf8_next_char(cursor);
  }
  return index;
}

void append_segments(FlValue* segments, const gchar* text, PangoAttrList* attrs) {
  if (!attrs) return;

  const size_t size = std::strlen(text);
  const gchar* cursor = text;
  gint64 index = 0;
  auto* it = pango_attr_list_get_iterator(attrs);
  do {
    gint start, end;
    pango_attr_iterator_range(it, &start, &end);
    const auto* from = text + std::min(size, static_cast<size_t>(start));
    const auto* to = text + std::min(size, static_cast<size_t>(end));
    if (from == to) continue;

    const bool selected = pango_attr_iterator_get(it, PANGO_ATTR_BACKGROUND);
    const bool styled = selected ||
        pango_attr_iterator_get(it, PANGO_ATTR_UNDERLINE) ||
        pango_attr_iterator_get(it, PANGO_ATTR_FOREGROUND) ||
        pango_attr_iterator_get(it, PANGO_ATTR_WEIGHT);
    if (!styled) continue;

    const auto first = advance_utf16(cursor, index, from);
    const auto last = advance_utf16(cursor, index, to);
    auto* segment = fl_value_new_map();
    fl_value_set_string_take(segment, "start", fl_value_new_int(first));
    fl_value_set_string_take(segment, "end", fl_value_new_int(last));
    fl_value_set_string_take(segment, "selected", fl_value_new_bool(selected));
    fl_value_append_take(segments, segment);
  } while (pango_attr_iterator_next(it));
  pango_attr_iterator_destroy(it);
}

class NativeTextInput {
 public:
  NativeTextInput(GtkWindow* window, GtkWidget* view, FlMethodChannel* channel)
      : window_(window), view_(view), channel_(channel) {}

  ~NativeTextInput() {
    stop();
    g_object_unref(channel_);
  }

  void stop() {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr, nullptr);
    client_ = 0;
    drop_context();
  }

  void update_focus() {
    auto* focus = gtk_window_get_focus(window_);
    auto* client_window = gtk_widget_get_window(GTK_WIDGET(window_));
    if (!client_ || !client_window || !gtk_window_has_toplevel_focus(window_) ||
        !focus || (focus != view_ && !gtk_widget_is_ancestor(focus, view_))) {
      if (context_) send_preedit("", 0, nullptr);
      drop_context();
      return;
    }
    if (context_) return;

    context_ = gtk_im_multicontext_new();
    g_signal_connect(context_, "commit", G_CALLBACK(committed), this);
    g_signal_connect(context_, "preedit-changed", G_CALLBACK(preedit_changed), this);
    g_signal_connect(context_, "preedit-end", G_CALLBACK(preedit_ended), this);
    gtk_im_context_set_client_window(context_, client_window);
    update_cursor();
    gtk_im_context_focus_in(context_);
  }

  gboolean filter_key(GdkEventKey* event) {
    return context_ && gtk_im_context_filter_keypress(context_, event);
  }

  void call(FlMethodCall* call) {
    auto* args = fl_method_call_get_args(call);
    auto* client = field(args, "client");
    if (!client || fl_value_get_type(client) != FL_VALUE_TYPE_INT ||
        fl_value_get_int(client) <= 0) {
      fl_method_call_respond_error(call, "invalid-arguments",
                                   "Expected a positive input client ID", nullptr, nullptr);
      return;
    }

    const auto id = fl_value_get_int(client);
    const char* method = fl_method_call_get_name(call);
    if (g_str_equal(method, "open")) {
      if (client_ != id) {
        drop_context();
        caret_ = {};
        client_ = id;
        update_focus();
      }
    } else if (g_str_equal(method, "close")) {
      if (client_ == id) {
        client_ = 0;
        drop_context();
      }
    } else if (g_str_equal(method, "geometry")) {
      if (client_ == id &&
          (rectangle(field(args, "caret"), &caret_) ||
           rectangle(field(args, "composing"), &caret_)))
        update_cursor();
    } else {
      fl_method_call_respond_not_implemented(call, nullptr);
      return;
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
  }

 private:
  GtkWindow* window_;
  GtkWidget* view_;
  FlMethodChannel* channel_;
  GtkIMContext* context_ = nullptr;
  gint64 client_ = 0;
  GdkRectangle caret_ = {};

  void drop_context() {
    auto* context = g_steal_pointer(&context_);
    if (!context) return;
    gtk_im_context_reset(context);
    gtk_im_context_focus_out(context);
    gtk_im_context_set_client_window(context, nullptr);
    g_object_unref(context);
  }

  void update_cursor() {
    if (!context_ || caret_.width == 0) return;
    gint x, y;
    if (!gtk_widget_translate_coordinates(view_, GTK_WIDGET(window_), 0, 0, &x, &y))
      return;
    GdkRectangle rect = caret_;
    rect.x = pixels(static_cast<double>(rect.x) + x);
    rect.y = pixels(static_cast<double>(rect.y) + y);
    gtk_im_context_set_cursor_location(context_, &rect);
  }

  FlValue* text_args(const gchar* text) {
    auto* args = fl_value_new_map();
    fl_value_set_string_take(args, "client", fl_value_new_int(client_));
    fl_value_set_string_take(args, "text", fl_value_new_string(text));
    return args;
  }

  void send_preedit(const gchar* text, gint cursor_index, PangoAttrList* attrs) {
    const auto count = g_utf8_strlen(text, -1);
    const auto* caret = g_utf8_offset_to_pointer(text, std::max<glong>(
        0, std::min<glong>(count, cursor_index)));
    const auto* first = text;
    gint64 cursor = 0;
    advance_utf16(first, cursor, caret);
    g_autoptr(FlValue) args = text_args(text);
    fl_value_set_string_take(args, "selectionStart", fl_value_new_int(cursor));
    fl_value_set_string_take(args, "selectionEnd", fl_value_new_int(cursor));
    auto* segments = fl_value_new_list();
    append_segments(segments, text, attrs);
    fl_value_set_string_take(args, "segments", segments);
    fl_method_channel_invoke_method(channel_, "preedit", args, nullptr, nullptr, nullptr);
  }

  static void committed(GtkIMContext* context, const gchar* text, gpointer data) {
    auto* input = static_cast<NativeTextInput*>(data);
    if (input->context_ != context) return;
    g_autoptr(FlValue) args = input->text_args(text);
    fl_method_channel_invoke_method(input->channel_, "commit", args, nullptr, nullptr, nullptr);
  }

  static void preedit_changed(GtkIMContext* context, gpointer data) {
    auto* input = static_cast<NativeTextInput*>(data);
    if (input->context_ != context) return;
    g_autofree gchar* text = nullptr;
    g_autoptr(PangoAttrList) attrs = nullptr;
    gint cursor = 0;
    gtk_im_context_get_preedit_string(context, &text, &attrs, &cursor);
    input->send_preedit(text, cursor, attrs);
  }

  static void preedit_ended(GtkIMContext* context, gpointer data) {
    auto* input = static_cast<NativeTextInput*>(data);
    if (input->context_ == context) input->send_preedit("", 0, nullptr);
  }
};
}  // namespace

void nauvim_register_native_text_input(FlView* view, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  auto* channel = fl_method_channel_new(
      messenger, "nauvim/native_text_input", FL_METHOD_CODEC(codec));
  auto* input = new NativeTextInput(window, GTK_WIDGET(view), channel);
  fl_method_channel_set_method_call_handler(
      channel, +[](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        static_cast<NativeTextInput*>(data)->call(call);
      }, input, nullptr);
  auto key = +[](GtkWidget*, GdkEventKey* event, gpointer data) -> gboolean {
    return static_cast<NativeTextInput*>(data)->filter_key(event);
  };
  g_signal_connect(window, "key-press-event", G_CALLBACK(key), input);
  g_signal_connect(window, "key-release-event", G_CALLBACK(key), input);
  g_signal_connect_after(window, "set-focus",
      G_CALLBACK(+[](GtkWindow*, GtkWidget*, gpointer data) {
        static_cast<NativeTextInput*>(data)->update_focus();
      }), input);
  g_signal_connect(window, "notify::has-toplevel-focus",
      G_CALLBACK(+[](GtkWindow*, GParamSpec*, gpointer data) {
        static_cast<NativeTextInput*>(data)->update_focus();
      }), input);
  g_signal_connect(window, "destroy", G_CALLBACK(+[](GtkWidget*, gpointer data) {
    static_cast<NativeTextInput*>(data)->stop();
  }), input);
  g_object_set_data_full(G_OBJECT(window), "nauvim-native-text-input", input,
      +[](gpointer data) { delete static_cast<NativeTextInput*>(data); });
}
