#include "renderer_policy.h"

#include <glib.h>

namespace {

bool is_card(const char* name) {
  if (!g_str_has_prefix(name, "card")) return false;
  const char* digit = name + 4;
  if (*digit == '\0') return false;
  for (; *digit != '\0'; ++digit) {
    if (*digit < '0' || *digit > '9') return false;
  }
  return true;
}

}  // namespace

bool nauvim_needs_renderer_workaround(const char* engine_revision,
                                     bool is_x11,
                                     bool has_renderer_override) {
  // This official Flutter 3.50.0 engine shifts shader-composited layers.
  // Corrected engines must keep GPU rendering: flutter/flutter#196418.
  return !has_renderer_override && is_x11 &&
         g_strcmp0(engine_revision,
                   "371f77202a73e8dff57a8b3bff75bca55c090aee") == 0;
}

bool nauvim_has_single_nvidia_adapter(const char* drm_directory) {
  g_autoptr(GDir) directory = g_dir_open(drm_directory, 0, nullptr);
  if (directory == nullptr) return false;

  g_autofree char* card = nullptr;
  while (const char* name = g_dir_read_name(directory)) {
    if (!is_card(name)) continue;
    // A loaded NVIDIA module does not identify the active GPU on hybrids.
    if (card != nullptr) return false;
    card = g_strdup(name);
  }
  if (card == nullptr) return false;

  g_autofree char* vendor_path =
      g_build_filename(drm_directory, card, "device", "vendor", nullptr);
  g_autofree char* vendor = nullptr;
  if (!g_file_get_contents(vendor_path, &vendor, nullptr, nullptr) ||
      g_strcmp0(g_strstrip(vendor), "0x10de") != 0) {
    return false;
  }
  g_autofree char* driver_path =
      g_build_filename(drm_directory, card, "device", "driver", nullptr);
  g_autofree char* driver = g_file_read_link(driver_path, nullptr);
  if (driver == nullptr) return false;
  g_autofree char* driver_name = g_path_get_basename(driver);
  return g_strcmp0(driver_name, "nvidia") == 0;
}
