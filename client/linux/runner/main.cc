#include "my_application.h"

// The boot splash is painted as an in-window overlay (see my_application.cc),
// not the native_splash_screen plugin's separate top-level window, which on
// GNOME/Wayland showed a rounded-corner/shadow frame and a peeking edge.
int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
