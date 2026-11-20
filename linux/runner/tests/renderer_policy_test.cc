#include "renderer_policy.h"

#include <glib.h>
#include <glib/gstdio.h>
#include <unistd.h>

namespace {

constexpr char kBrokenEngine[] = "371f77202a73e8dff57a8b3bff75bca55c090aee";

void remove_tree(const char* path) {
  if (g_file_test(path, G_FILE_TEST_IS_SYMLINK) ||
      !g_file_test(path, G_FILE_TEST_IS_DIR)) {
    g_assert_cmpint(g_remove(path), ==, 0);
    return;
  }
  {
    g_autoptr(GDir) directory = g_dir_open(path, 0, nullptr);
    g_assert_nonnull(directory);
    while (const char* name = g_dir_read_name(directory)) {
      g_autofree char* child = g_build_filename(path, name, nullptr);
      remove_tree(child);
    }
  }
  g_assert_cmpint(g_rmdir(path), ==, 0);
}

class Drm {
 public:
  Drm() : path_(g_dir_make_tmp("nauvim-renderer-test-XXXXXX", nullptr)) {
    g_assert_nonnull(path_);
  }
  ~Drm() {
    remove_tree(path_);
    g_free(path_);
  }
  Drm(const Drm&) = delete;
  Drm& operator=(const Drm&) = delete;

  const char* path() const { return path_; }

  void card(const char* name, const char* vendor, const char* driver) {
    g_autofree char* device = g_build_filename(path_, name, "device", nullptr);
    g_assert_cmpint(g_mkdir_with_parents(device, 0700), ==, 0);
    if (vendor != nullptr) {
      g_autofree char* file = g_build_filename(device, "vendor", nullptr);
      g_assert_true(g_file_set_contents(file, vendor, -1, nullptr));
    }
    if (driver != nullptr) {
      g_autofree char* link = g_build_filename(device, "driver", nullptr);
      g_autofree char* target = g_build_filename("/drivers", driver, nullptr);
      g_assert_cmpint(symlink(target, link), ==, 0);
    }
  }

 private:
  char* path_;
};

void engine_policy() {
  g_assert_true(nauvim_needs_renderer_workaround(kBrokenEngine, true, false));
  g_assert_false(nauvim_needs_renderer_workaround(kBrokenEngine, false, false));
  // Presence of the environment variable, including an empty value, wins.
  g_assert_false(nauvim_needs_renderer_workaround(kBrokenEngine, true, true));
  const char* revisions[] = {
      nullptr, "", "unknown", "4d35714800b9266b6693a58e1225ecd7e9e45ed7"};
  for (const char* revision : revisions) {
    g_assert_false(nauvim_needs_renderer_workaround(revision, true, false));
  }
}

void single_nvidia() {
  Drm drm;
  drm.card("card12", "0x10de\n", "nvidia");
  drm.card("card12-HDMI-A-1", nullptr, nullptr);
  drm.card("renderD128", nullptr, nullptr);
  drm.card("card", nullptr, nullptr);
  g_assert_true(nauvim_has_single_nvidia_adapter(drm.path()));
}

void ambiguous_adapters() {
  Drm drm;
  drm.card("card0", "0x10de\n", "nvidia");
  drm.card("card1", "0x8086\n", "i915");
  g_assert_false(nauvim_has_single_nvidia_adapter(drm.path()));
}

void other_or_missing_driver() {
  const char* vendors[] = {"0x10de\n", "0x1002\n", "0x10de\n", nullptr};
  const char* drivers[] = {"nouveau", "amdgpu", nullptr, "nvidia"};
  for (unsigned i = 0; i < G_N_ELEMENTS(vendors); ++i) {
    Drm drm;
    drm.card("card0", vendors[i], drivers[i]);
    g_assert_false(nauvim_has_single_nvidia_adapter(drm.path()));
  }
  Drm empty;
  g_assert_false(nauvim_has_single_nvidia_adapter(empty.path()));
  g_autofree char* missing = g_build_filename(empty.path(), "missing", nullptr);
  g_assert_false(nauvim_has_single_nvidia_adapter(missing));
}

}  // namespace

int main(int argc, char** argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/renderer/engine_policy", engine_policy);
  g_test_add_func("/renderer/single_nvidia", single_nvidia);
  g_test_add_func("/renderer/ambiguous_adapters", ambiguous_adapters);
  g_test_add_func("/renderer/other_or_missing_driver", other_or_missing_driver);
  return g_test_run();
}
