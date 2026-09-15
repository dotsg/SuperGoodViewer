#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <sys/stat.h>
#include <unistd.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  GtkHeaderBar* header_bar;
  FlMethodChannel* window_channel;
  FlMethodChannel* app_channel;
  gchar* pending_file;
  gboolean is_fullscreen;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Forward declarations
static void window_channel_method_call_cb(FlMethodChannel* channel,
                                          FlMethodCall* method_call,
                                          gpointer user_data);
static void app_channel_method_call_cb(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data);
static gboolean window_state_event_cb(GtkWidget* widget,
                                      GdkEventWindowState* event,
                                      gpointer user_data);

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static gchar* get_linux_cli_target_script() {
  gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    gchar* exe_dir = g_path_get_dirname(exe_path);
    gchar* candidate = g_build_filename(exe_dir, "bin", "sgv", nullptr);
    g_free(exe_path);
    g_free(exe_dir);
    if (g_file_test(candidate, G_FILE_TEST_EXISTS)) {
      return candidate;
    }
    g_free(candidate);
  }
  g_autofree gchar* cwd = g_get_current_dir();
  gchar* candidate = g_build_filename(cwd, "ui", "bin", "sgv", nullptr);
  if (g_file_test(candidate, G_FILE_TEST_EXISTS)) {
    return candidate;
  }
  g_free(candidate);
  return nullptr;
}

static gchar* get_linux_user_cli_symlink() {
  const gchar* home = g_get_home_dir();
  return g_build_filename(home, ".local", "bin", "sgv", nullptr);
}

static FlValue* check_cli_status() {
  FlValue* map = fl_value_new_map();
  gchar* symlink_path = get_linux_user_cli_symlink();
  gchar* target = get_linux_cli_target_script();

  gboolean is_installed = FALSE;
  gchar* current_target = nullptr;

  if (g_file_test(symlink_path, G_FILE_TEST_EXISTS) || g_file_test(symlink_path, G_FILE_TEST_IS_SYMLINK)) {
    is_installed = TRUE;
    current_target = g_file_read_link(symlink_path, nullptr);
  }

  fl_value_set_string_take(map, "isInstalled", fl_value_new_bool(is_installed));
  fl_value_set_string_take(map, "path", fl_value_new_string(symlink_path));
  fl_value_set_string_take(map, "target", fl_value_new_string(current_target ? current_target : (target ? target : "")));
  fl_value_set_string_take(map, "isCurrentApp", fl_value_new_bool(is_installed));

  g_free(symlink_path);
  g_free(target);
  g_free(current_target);
  return map;
}

static FlValue* install_cli() {
  FlValue* map = fl_value_new_map();
  gchar* symlink_path = get_linux_user_cli_symlink();
  gchar* target = get_linux_cli_target_script();

  if (target == nullptr) {
    fl_value_set_string_take(map, "status", fl_value_new_string("error"));
    fl_value_set_string_take(map, "message", fl_value_new_string("未能定位 sgv 启动脚本"));
    g_free(symlink_path);
    return map;
  }

  // Ensure ~/.local/bin directory exists
  gchar* bin_dir = g_path_get_dirname(symlink_path);
  g_mkdir_with_parents(bin_dir, 0755);
  g_free(bin_dir);

  unlink(symlink_path);

  if (symlink(target, symlink_path) == 0) {
    fl_value_set_string_take(map, "status", fl_value_new_string("success"));
    fl_value_set_string_take(map, "path", fl_value_new_string(symlink_path));
  } else {
    fl_value_set_string_take(map, "status", fl_value_new_string("error"));
    fl_value_set_string_take(map, "message", fl_value_new_string("创建符号链接失败"));
  }

  g_free(symlink_path);
  g_free(target);
  return map;
}

static FlValue* uninstall_cli() {
  FlValue* map = fl_value_new_map();
  gchar* symlink_path = get_linux_user_cli_symlink();
  unlink(symlink_path);
  unlink("/usr/local/bin/sgv");

  fl_value_set_string_take(map, "status", fl_value_new_string("success"));
  g_free(symlink_path);
  return map;
}

static void window_channel_method_call_cb(FlMethodChannel* channel,
                                          FlMethodCall* method_call,
                                          gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (g_strcmp0(method, "toggleFullScreen") == 0) {
    if (self->is_fullscreen) {
      gtk_window_unfullscreen(self->window);
      self->is_fullscreen = FALSE;
    } else {
      gtk_window_fullscreen(self->window);
      self->is_fullscreen = TRUE;
    }
    g_autoptr(FlValue) res = fl_value_new_bool(self->is_fullscreen);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(res));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (g_strcmp0(method, "isFullScreen") == 0) {
    g_autoptr(FlValue) res = fl_value_new_bool(self->is_fullscreen);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(res));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (g_strcmp0(method, "startDragging") == 0) {
    GdkEvent* event = gtk_get_current_event();
    if (event != nullptr) {
      gdouble x_root = 0, y_root = 0;
      guint button = 1;
      guint32 time = gdk_event_get_time(event);
      gdk_event_get_root_coords(event, &x_root, &y_root);
      if (event->type == GDK_BUTTON_PRESS || event->type == GDK_2BUTTON_PRESS) {
        button = event->button.button;
      }
      gtk_window_begin_move_drag(self->window, button, (gint)x_root, (gint)y_root, time);
      gdk_event_free(event);
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (g_strcmp0(method, "zoom") == 0) {
    if (gtk_window_is_maximized(self->window)) {
      gtk_window_unmaximize(self->window);
    } else {
      gtk_window_maximize(self->window);
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (g_strcmp0(method, "setTrafficLightsVisible") == 0) {
    // No macOS traffic lights on Linux; no-op
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (g_strcmp0(method, "setWindowTitle") == 0) {
    if (fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      const gchar* title = fl_value_get_string(args);
      gtk_window_set_title(self->window, title);
      if (self->header_bar != nullptr) {
        gtk_header_bar_set_title(self->header_bar, title);
      }
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

static void app_channel_method_call_cb(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "getInitialFile") == 0) {
    g_autoptr(FlMethodResponse) response = nullptr;
    if (self->pending_file != nullptr && strlen(self->pending_file) > 0) {
      g_autoptr(FlValue) val = fl_value_new_string(self->pending_file);
      g_clear_pointer(&self->pending_file, g_free);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(val));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    fl_method_call_respond(method_call, response, nullptr);
  } else if (g_strcmp0(method, "checkCliStatus") == 0) {
    g_autoptr(FlValue) res = check_cli_status();
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(res));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (g_strcmp0(method, "installCli") == 0) {
    g_autoptr(FlValue) res = install_cli();
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(res));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (g_strcmp0(method, "uninstallCli") == 0) {
    g_autoptr(FlValue) res = uninstall_cli();
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(res));
    fl_method_call_respond(method_call, response, nullptr);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

static gboolean window_state_event_cb(GtkWidget* widget,
                                      GdkEventWindowState* event,
                                      gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (event->changed_mask & GDK_WINDOW_STATE_FULLSCREEN) {
    gboolean is_fs = (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
    self->is_fullscreen = is_fs;
    if (self->window_channel != nullptr) {
      g_autoptr(FlValue) val = fl_value_new_bool(is_fs);
      fl_method_channel_invoke_method(self->window_channel, "onFullScreenChanged", val,
                                      nullptr, nullptr, nullptr);
    }
  }
  return FALSE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    gtk_window_present(self->window);
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    self->header_bar = header_bar;
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "SuperGoodViewer");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "SuperGoodViewer");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Initialize Method Channels
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  self->window_channel = fl_method_channel_new(
      messenger, "com.sogoodviewer.window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_channel_method_call_cb, self, nullptr);

  self->app_channel = fl_method_channel_new(
      messenger, "com.sogoodviewer.app", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->app_channel, app_channel_method_call_cb, self, nullptr);

  g_signal_connect(window, "window-state-event", G_CALLBACK(window_state_event_cb), self);

  if (self->pending_file != nullptr) {
    g_autoptr(FlValue) val = fl_value_new_string(self->pending_file);
    fl_method_channel_invoke_method(self->app_channel, "onOpenFile", val,
                                    nullptr, nullptr, nullptr);
  }

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::open for single instance file opening.
static void my_application_open(GApplication* application,
                                GFile** files,
                                gint n_files,
                                const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);
  for (gint i = 0; i < n_files; i++) {
    gchar* path = g_file_get_path(files[i]);
    if (path != nullptr) {
      if (self->app_channel != nullptr) {
        g_autoptr(FlValue) val = fl_value_new_string(path);
        fl_method_channel_invoke_method(self->app_channel, "onOpenFile", val,
                                        nullptr, nullptr, nullptr);
      } else {
        g_free(self->pending_file);
        self->pending_file = g_strdup(path);
      }
      g_free(path);
    }
  }
  if (self->window != nullptr) {
    gtk_window_present(self->window);
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  gchar** args = *arguments;
  if (args != nullptr && args[0] != nullptr) {
    for (int i = 1; args[i] != nullptr; i++) {
      if (args[i][0] != '-' && g_file_test(args[i], G_FILE_TEST_EXISTS)) {
        g_free(self->pending_file);
        self->pending_file = g_canonicalize_filename(args[i], nullptr);
        break;
      }
    }
  }

  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  if (g_application_get_is_remote(application)) {
    if (self->pending_file != nullptr) {
      g_autoptr(GFile) file = g_file_new_for_path(self->pending_file);
      GFile* files[1] = { file };
      g_application_open(application, files, 1, "");
    } else {
      g_application_activate(application);
    }
    *exit_status = 0;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->pending_file, g_free);
  g_clear_object(&self->window_channel);
  g_clear_object(&self->app_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->is_fullscreen = FALSE;
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_HANDLES_OPEN,
                                     nullptr));
}
