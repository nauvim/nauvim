#ifndef NAUVIM_RENDERER_POLICY_H_
#define NAUVIM_RENDERER_POLICY_H_

bool nauvim_needs_renderer_workaround(const char* engine_revision,
                                     bool is_x11,
                                     bool has_renderer_override);
bool nauvim_has_single_nvidia_adapter(const char* drm_directory);

#endif  // NAUVIM_RENDERER_POLICY_H_
