/***
  Copyright (C) 2014 Kiran John Hampal <kiran@elementaryos.org>

  This program is free software: you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public License version 3, as published
  by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranties of
  MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
  PURPOSE. See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with program. If not, see <http://www.gnu.org/licenses>
***/

class Taxi.MainWindow : Adw.ApplicationWindow {
    public IConnectionSaver conn_saver { get; construct; }
    public IFileOperations file_operation { get; construct; }
    public IFileAccess local_access { get; construct; }
    public IFileAccess remote_access { get; construct; }

    private Adw.ToastOverlay toasts;
    private Gtk.Revealer spinner_revealer;
    private Gtk.ListBox bookmark_list;
    private Gtk.Box outer_box;
    private Gtk.MenuButton bookmark_menu_button;
    private Gtk.Stack alert_stack;
    private ConnectBox connect_box;
    private Adw.StatusPage welcome;
    private FilePane local_pane;
    private FilePane remote_pane;
    private Soup.URI conn_uri;
    private GLib.Settings saved_state;
    private Gtk.EventControllerKey key_controller;
    private int overwrite_response = 0;
    private bool overwrite_done = false;

    public MainWindow (
        Gtk.Application application,
        IFileAccess local_access,
        IFileAccess remote_access,
        IFileOperations file_operation,
        IConnectionSaver conn_saver
    ) {
        Object (
            application: application,
            conn_saver: conn_saver,
            file_operation: file_operation,
            local_access: local_access,
            remote_access: remote_access
        );
    }

    construct {
        connect_box = new ConnectBox ();
        connect_box.valign = Gtk.Align.CENTER;

        var spinner = new Gtk.Spinner ();
        spinner.start ();

        var popover = new OperationsPopover (spinner);

        var operations_button = new Gtk.MenuButton ();
        operations_button.popover = popover;
        operations_button.valign = Gtk.Align.CENTER;
        operations_button.add_css_class ("flat");
        operations_button.set_child (spinner);

        spinner_revealer = new Gtk.Revealer ();
        spinner_revealer.transition_type = Gtk.RevealerTransitionType.SLIDE_RIGHT;
        spinner_revealer.set_child (operations_button);

        var bookmark_scrollbox = new Gtk.ScrolledWindow ();
        bookmark_scrollbox.hscrollbar_policy = Gtk.PolicyType.NEVER;
        bookmark_scrollbox.max_content_height = 500;
        bookmark_scrollbox.propagate_natural_height = true;

        var bookmark_popover = new Gtk.Popover ();
        bookmark_popover.add_css_class ("menu");
        bookmark_popover.set_child (bookmark_scrollbox);

        bookmark_list = new Gtk.ListBox ();
        bookmark_list.margin_top = bookmark_list.margin_bottom = 3;
        bookmark_list.selection_mode = Gtk.SelectionMode.NONE;
        bookmark_list.row_activated.connect ((row) => {
            var uri = row.get_data<string> ("uri");
            connect_box.go_to_uri (uri);
            bookmark_popover.hide ();
        });
        bookmark_scrollbox.set_child (bookmark_list);

        bookmark_menu_button = new Gtk.MenuButton ();
        bookmark_menu_button.icon_name = "user-bookmarks-symbolic";
        bookmark_menu_button.popover = bookmark_popover;
        bookmark_menu_button.tooltip_text = _("Access Bookmarks");

        update_bookmark_menu ();

        var header_bar = new Adw.HeaderBar ();
        var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        header_box.append (connect_box);
        header_box.append (spinner_revealer);
        header_box.append (bookmark_menu_button);
        header_bar.set_title_widget (header_box);

        welcome = new Adw.StatusPage ();
        welcome.title = _("Connect");
        welcome.description =  _("Type a URL and press 'Enter' to connect to a server.");
        welcome.vexpand = true;

        local_pane = new FilePane ();
        local_pane.location = Location.LOCAL;
        local_pane.file_dragged.connect (on_local_file_dragged);
        local_pane.transfer.connect (on_remote_file_dragged);
        local_access.directory_changed.connect (() => update_pane (Location.LOCAL));

        remote_pane = new FilePane ();
        remote_pane.location = Location.REMOTE;
        remote_pane.file_dragged.connect (on_remote_file_dragged);
        remote_pane.transfer.connect (on_local_file_dragged);

        outer_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        outer_box.append (local_pane);
        outer_box.append (new Gtk.Separator (Gtk.Orientation.VERTICAL));
        outer_box.append (remote_pane);

        var size_group = new Gtk.SizeGroup (Gtk.SizeGroupMode.HORIZONTAL);
        size_group.add_widget (local_pane);
        size_group.add_widget (remote_pane);

        alert_stack = new Gtk.Stack ();
        alert_stack.add_child (welcome);
        alert_stack.add_child (outer_box);

        toasts = new Adw.ToastOverlay ();
        toasts.set_child (alert_stack);

        var grid = new Gtk.Grid ();
        grid.attach (header_bar, 0, 0);
        grid.attach (toasts, 0, 1);

        set_content (grid);

        saved_state = new GLib.Settings ("com.github.alecaddd.taxi.state");

        saved_state.bind ("window-width", this,
                   "default-width", SettingsBindFlags.DEFAULT);
        saved_state.bind ("window-height", this,
                    "default-height", SettingsBindFlags.DEFAULT);
        saved_state.bind ("maximized", this,
                    "maximized", SettingsBindFlags.DEFAULT);

        key_controller = new Gtk.EventControllerKey ();

        key_controller.key_pressed.connect (connect_box.on_key_press_event);

        connect_box.connect_initiated.connect (on_connect_initiated);
        connect_box.ask_hostname.connect (on_ask_hostname);
        connect_box.bookmarked.connect (bookmark);

        file_operation.operation_added.connect (popover.add_operation);
        file_operation.operation_removed.connect (popover.remove_operation);
        file_operation.ask_overwrite.connect (on_ask_overwrite);

        popover.operations_pending.connect (show_spinner);
        popover.operations_finished.connect (hide_spinner);

        var open_local_action = new SimpleAction ("open-local", new VariantType("s"));
        open_local_action.activate.connect ( (action, value) => {
            var uri = new Soup.URI (value.get_string ());
            local_access.open_file (uri);
        });
        add_action (open_local_action);

        var navigate_local_action = new SimpleAction ("navigate-local", null);
        navigate_local_action.activate.connect ( (value) => {
            var uri = new Soup.URI (value.get_string ());
            navigate (uri, local_access, Location.LOCAL);
        });
        add_action (navigate_local_action);

        var delete_local_action = new SimpleAction ("delete-local", new VariantType("s"));
        delete_local_action.activate.connect ( (value) => {
            var uri = new Soup.URI (value.get_string ());
            file_delete (uri, Location.LOCAL);
        });
        add_action (delete_local_action);

        var open_remote_action = new SimpleAction ("open-remote", new VariantType("s"));
        open_remote_action.activate.connect ( (value) => {
            var uri = new Soup.URI (value.get_string ());
            remote_access.open_file (uri);
        });
        add_action (open_remote_action);

        var navigate_remote_action = new SimpleAction ("navigate-remote", new VariantType("s"));
        navigate_remote_action.activate.connect ( (value) => {
            var uri = new Soup.URI (value.get_string ());
            navigate (uri, remote_access, Location.REMOTE);
        });
        add_action (navigate_remote_action);

        var delete_remote_action = new SimpleAction ("delete-remote", new VariantType("s"));
        delete_remote_action.activate.connect ( (value) => {
            var uri = new Soup.URI (value.get_string ());
            file_delete (uri, Location.REMOTE);
        });
        add_action (delete_remote_action);
    }

    private void on_connect_initiated (Soup.URI uri) {
        show_spinner ();
        remote_access.connect_to_device.begin (uri, this, (obj, res) => {
            if (remote_access.connect_to_device.end (res)) {
                alert_stack.visible_child = outer_box;
                if (local_pane == null) {
                    key_controller.key_pressed.disconnect (connect_box.on_key_press_event);
                }
                update_pane (Location.LOCAL);
                update_pane (Location.REMOTE);
                connect_box.show_favorite_icon (
                    conn_saver.is_bookmarked (remote_access.get_uri ().to_string (false))
                );
                conn_uri = uri;
            } else {
                alert_stack.visible_child = welcome;
                welcome.title = _("Could not connect to '%s'").printf (uri.to_string (false));
            }
            hide_spinner ();
        });
    }

    private void show_spinner () {
        spinner_revealer.reveal_child = true;
    }

    private void hide_spinner () {
        spinner_revealer.reveal_child = false;
    }

    private void bookmark () {
        var uri_string = conn_uri.to_string (false);
        if (conn_saver.is_bookmarked (uri_string)) {
            conn_saver.remove (uri_string);
        } else {
            conn_saver.save (uri_string);
        }
        connect_box.show_favorite_icon (
            conn_saver.is_bookmarked (uri_string)
        );
        update_bookmark_menu ();
    }

    private void update_bookmark_menu () {
        var row = bookmark_list.get_row_at_index (0);
        while (row != null) {
            bookmark_list.remove (row);
            row = bookmark_list.get_row_at_index (0);
        }

        var uri_list = conn_saver.get_saved_conns ();
        if (uri_list.length () == 0) {
            bookmark_menu_button.sensitive = false;
        } else {
            foreach (string uri in uri_list) {
                var bookmark_item = new Gtk.ListBoxRow ();
                var label = new Gtk.Label (uri);
                bookmark_item.set_child (label);
                bookmark_item.set_data ("uri", uri);
                bookmark_item.activatable = true;

                bookmark_list.append (bookmark_item);
            }
            bookmark_menu_button.sensitive = true;
        }
    }

    private void on_remote_file_dragged (string uri) {
        file_dragged (uri, Location.REMOTE, remote_access);
    }

    private void on_local_file_dragged (string uri) {
        file_dragged (uri, Location.LOCAL, local_access);
    }

    private void navigate (Soup.URI uri, IFileAccess file_access, Location pane) {
        file_access.goto_dir (uri);
        update_pane (pane);
    }

    private void file_dragged (
        string uri,
        Location pane,
        IFileAccess file_access
    ) {
        var source_file = File.new_for_uri (uri.replace ("\r\n", ""));
        var dest_file = file_access.get_current_file ().get_child (source_file.get_basename ());
        file_operation.copy_recursive.begin (
            source_file,
            dest_file,
            FileCopyFlags.NONE,
            new Cancellable (),
            (obj, res) => {
                try {
                    file_operation.copy_recursive.end (res);
                    update_pane (pane);
                } catch (Error e) {
                    var toast = new Adw.Toast(e.message);
                    toasts.add_toast (toast);
                }
            }
         );
    }

    private void file_delete (Soup.URI uri, Location pane) {
        var file = File.new_for_uri (uri.to_string (false));
        file_operation.delete_recursive.begin (
            file,
            new Cancellable (),
            (obj, res) => {
                try {
                    file_operation.delete_recursive.end (res);
                    update_pane (pane);
                } catch (Error e) {
                    var toast = new Adw.Toast(e.message);
                    toasts.add_toast (toast);
                }
            }
        );
    }

    private void update_pane (Location pane) {
        IFileAccess file_access;
        FilePane file_pane;
        switch (pane) {
            case Location.REMOTE:
                file_access = remote_access;
                file_pane = remote_pane;
                break;
            case Location.LOCAL:
            default:
                file_access = local_access;
                file_pane = local_pane;
                break;
        }
        file_pane.start_spinner ();
        var file_uri = file_access.get_uri ();
        file_access.get_file_list.begin ((obj, res) => {
        var file_files = file_access.get_file_list.end (res);
            file_pane.stop_spinner ();
            file_pane.update_pathbar (file_uri);
            file_pane.update_list (file_files);
        });
    }

    private Soup.URI on_ask_hostname () {
        return conn_uri;
    }

    private int on_ask_overwrite (File destination) {
        var dialog = new Gtk.MessageDialog (
            this,
            Gtk.DialogFlags.MODAL,
            Gtk.MessageType.QUESTION,
            Gtk.ButtonsType.NONE,
            _("Replace existing file?")
        );
        dialog.format_secondary_markup (
            _("<i>\"%s\"</i> already exists. You can replace this file, replace all conflicting files or choose not to replace the file by skipping.".printf (destination.get_basename ()))
        );
        dialog.add_button (_("Replace All Conflicts"), 2);
        dialog.add_button (_("Skip"), 0);
        dialog.add_button (_("Replace"), 1);
        dialog.get_widget_for_response (1).add_css_class ("suggested-action");

        dialog.response.connect (on_overwrite_response);

        dialog.present ();

        while (!overwrite_done) {
            MainContext.@default ().iteration (true);
        }

        overwrite_done = false;
        return overwrite_response;
    }

    private void on_overwrite_response(Gtk.Dialog dialog, int response) {
        overwrite_response = response;
        overwrite_done = true;
        dialog.destroy ();
    }
}
