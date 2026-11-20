#ifndef NAUVIM_WEBVIEWS_H_
#define NAUVIM_WEBVIEWS_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
void nauvim_register_windows(FlView* view, GtkWindow* window, GtkOverlay* overlay);
#endif
