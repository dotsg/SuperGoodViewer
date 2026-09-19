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

static gboolean target_file_exists(const gchar* target, const gchar* link_dir) {
  if (target == nullptr) return FALSE;
  gchar* full_path = nullptr;
  if (g_path_is_absolute(target)) {
    full_path = g_strdup(target);
  } else {
    full_path = g_build_filename(link_dir, target, nullptr);
  }
  gboolean exists = g_file_test(full_path, G_FILE_TEST_EXISTS);
  g_free(full_path);
  return exists;
}

static FlValue* check_cli_status() {
  FlValue* map = fl_value_new_map();
  gchar* symlink_path = get_linux_user_cli_symlink();
  gchar* target = get_linux_cli_target_script();

  const gchar* home = g_get_home_dir();
  gchar* cli_bin_symlink = g_build_filename(home, ".local", "bin", "sgv-cli", nullptr);
  gchar* target_dir = target ? g_path_get_dirname(target) : nullptr;
  gchar* cli_bin_target = target_dir ? g_build_filename(target_dir, "sgv-cli", nullptr) : nullptr;

  gboolean sgv_installed = g_file_test(symlink_path, G_FILE_TEST_EXISTS) ||
                           g_file_test(symlink_path, G_FILE_TEST_IS_SYMLINK);
  gboolean cli_bin_installed = g_file_test(cli_bin_symlink, G_FILE_TEST_EXISTS) ||
                               g_file_test(cli_bin_symlink, G_FILE_TEST_IS_SYMLINK);

  gboolean has_cli_bin = cli_bin_target && g_file_test(cli_bin_target, G_FILE_TEST_EXISTS);
  gboolean is_installed = has_cli_bin ? (sgv_installed && cli_bin_installed) : sgv_installed;
  gboolean is_partial = !is_installed && (sgv_installed || cli_bin_installed);

  gchar* current_target = nullptr;
  if (sgv_installed) {
    current_target = g_file_read_link(symlink_path, nullptr);
  }

  gboolean is_current_app = is_installed;
  if (is_installed && target && current_target) {
    gboolean sgv_match = (g_strcmp0(current_target, target) == 0) ||
                         (g_strstr_len(current_target, -1, "supergoodviewer") != nullptr) ||
                         (g_strstr_len(current_target, -1, "sogoodviewer") != nullptr);
    gboolean cli_bin_match = TRUE;
    if (has_cli_bin) {
      gchar* current_cli_bin_target = g_file_read_link(cli_bin_symlink, nullptr);
      if (current_cli_bin_target) {
        cli_bin_match = (g_strcmp0(current_cli_bin_target, cli_bin_target) == 0) ||
                        (g_strstr_len(current_cli_bin_target, -1, "supergoodviewer") != nullptr) ||
                        (g_strstr_len(current_cli_bin_target, -1, "sogoodviewer") != nullptr);
        g_free(current_cli_bin_target);
      } else {
        cli_bin_match = FALSE;
      }
    }
    is_current_app = sgv_match && cli_bin_match;
  }

  fl_value_set_string_take(map, "isInstalled", fl_value_new_bool(is_installed));
  fl_value_set_string_take(map, "isPartial", fl_value_new_bool(is_partial));
  fl_value_set_string_take(map, "path", fl_value_new_string(symlink_path));
  fl_value_set_string_take(map, "target", fl_value_new_string(current_target ? current_target : (target ? target : "")));
  fl_value_set_string_take(map, "isCurrentApp", fl_value_new_bool(is_current_app));
  if (is_partial) {
    fl_value_set_string_take(map, "warningCode", fl_value_new_string("incomplete_tools"));
    fl_value_set_string_take(map, "warning", fl_value_new_string("安装不完整 (部分工具未就绪)"));
  }

  g_free(symlink_path);
  g_free(cli_bin_symlink);
  g_free(target_dir);
  g_free(cli_bin_target);
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
    fl_value_set_string_take(map, "messageCode", fl_value_new_string("locate_launcher_failed"));
    fl_value_set_string_take(map, "message", fl_value_new_string("未能定位 sgv 启动脚本"));
    g_free(symlink_path);
    return map;
  }

  // Ensure ~/.local/bin directory exists
  gchar* bin_dir = g_path_get_dirname(symlink_path);
  g_mkdir_with_parents(bin_dir, 0755);
  g_free(bin_dir);

  gchar* old_sgv_target = g_file_read_link(symlink_path, nullptr);
  unlink(symlink_path);

  if (symlink(target, symlink_path) == 0) {
    gboolean cli_bin_failed = FALSE;
    // Also link sgv-cli binary if available adjacent to sgv
    gchar* target_dir = g_path_get_dirname(target);
    gchar* cli_bin_target = g_build_filename(target_dir, "sgv-cli", nullptr);
    const gchar* home = g_get_home_dir();
    gchar* cli_bin_symlink = g_build_filename(home, ".local", "bin", "sgv-cli", nullptr);

    if (g_file_test(cli_bin_target, G_FILE_TEST_EXISTS)) {
      gchar* old_cli_bin_target = g_file_read_link(cli_bin_symlink, nullptr);
      unlink(cli_bin_symlink);
      if (symlink(cli_bin_target, cli_bin_symlink) != 0) {
        cli_bin_failed = TRUE;
        if (old_cli_bin_target != nullptr) {
          gchar* link_dir = g_path_get_dirname(cli_bin_symlink);
          if (target_file_exists(old_cli_bin_target, link_dir)) {
            symlink(old_cli_bin_target, cli_bin_symlink);
          }
          g_free(link_dir);
        }
      }
      g_free(old_cli_bin_target);
    }
    g_free(target_dir);
    g_free(cli_bin_target);
    g_free(cli_bin_symlink);

    fl_value_set_string_take(map, "status", fl_value_new_string("success"));
    fl_value_set_string_take(map, "path", fl_value_new_string(symlink_path));
    if (cli_bin_failed) {
      fl_value_set_string_take(map, "warningCode", fl_value_new_string("cli_tool_failed"));
      FlValue* codes = fl_value_new_list();
      fl_value_append_take(codes, fl_value_new_string("cli_tool_failed"));
      fl_value_set_string_take(map, "warningCodes", codes);
      fl_value_set_string_take(map, "warning", fl_value_new_string("sgv 安装成功，但未能创建 sgv-cli 快捷方式"));
    }
  } else {
    // Restore previous sgv link if replacement failed and target still exists
    if (old_sgv_target != nullptr) {
      gchar* link_dir = g_path_get_dirname(symlink_path);
      if (target_file_exists(old_sgv_target, link_dir)) {
        symlink(old_sgv_target, symlink_path);
      }
      g_free(link_dir);
    }
    fl_value_set_string_take(map, "status", fl_value_new_string("error"));
    fl_value_set_string_take(map, "messageCode", fl_value_new_string("symlink_failed"));
    fl_value_set_string_take(map, "message", fl_value_new_string("创建符号链接失败"));
  }

  g_free(old_sgv_target);
  g_free(symlink_path);
  g_free(target);
  return map;
}

static FlValue* uninstall_cli() {
  FlValue* map = fl_value_new_map();
  gchar* symlink_path = get_linux_user_cli_symlink();
  unlink(symlink_path);
  unlink("/usr/local/bin/sgv");

  const gchar* home = g_get_home_dir();
  gchar* cli_bin_symlink = g_build_filename(home, ".local", "bin", "sgv-cli", nullptr);
  unlink(cli_bin_symlink);
  unlink("/usr/local/bin/sgv-cli");
  g_free(cli_bin_symlink);

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
