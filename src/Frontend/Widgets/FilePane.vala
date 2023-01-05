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
  with this program. If not, see <http://www.gnu.org/licenses>
***/

namespace Taxi {

    enum Target {
        STRING,
        URI_LIST;
    }

    class FilePane : Gtk.Box {
        private Soup.URI current_uri;
        private PathBar path_bar;
        private Gtk.ListBox list_box;
        private Gtk.Stack stack;
        private Gtk.DropTarget drop_target;

        public Location location;

        public signal void file_dragged (string uri);
        public signal void transfer (string uri);
        public signal void rename (Soup.URI uri);
        public signal void edit (Soup.URI uri);

        delegate void ActivateFunc (Soup.URI uri);

        construct {
            path_bar = new PathBar ();
            path_bar.hexpand = true;

            var placeholder_label = new Gtk.Label (_("This Folder Is Empty"));
            placeholder_label.halign = Gtk.Align.CENTER;
            placeholder_label.valign = Gtk.Align.CENTER;
            placeholder_label.show ();

            placeholder_label.add_css_class ("title-2");
            placeholder_label.add_css_class ("dim-label");

            list_box = new Gtk.ListBox ();
            list_box.hexpand = true;
            list_box.vexpand = true;
            list_box.set_placeholder (placeholder_label);
            list_box.set_selection_mode (Gtk.SelectionMode.MULTIPLE);

            var scrolled_pane = new Gtk.ScrolledWindow ();
            scrolled_pane.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scrolled_pane.set_child (list_box);

            var spinner = new Gtk.Spinner ();
            spinner.hexpand = true;
            spinner.vexpand = true;
            spinner.halign = Gtk.Align.CENTER;
            spinner.valign = Gtk.Align.CENTER;
            spinner.start ();

            stack = new Gtk.Stack ();
            stack.add_named (scrolled_pane, "list");
            stack.add_named (spinner, "spinner");

            var inner_grid = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            inner_grid.append (path_bar);
            inner_grid.append (stack);

            append (inner_grid);

            drop_target = new Gtk.DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop_target.on_drop.connect (on_drag_drop);
            list_box.add_controller (drop_target);

            list_box.row_activated.connect ((row) => {
                var uri = row.get_data<Soup.URI> ("uri");
                var type = row.get_data<FileType> ("type");
                if (type == FileType.DIRECTORY) {
                    navigate (uri);
                } else {
                    open (uri);
                }
            });

            path_bar.navigate.connect ((uri) => {
                navigate (uri);
            });
            path_bar.transfer.connect (on_pathbar_transfer);
        }

        private void on_pathbar_transfer () {
            foreach (string uri in get_marked_row_uris ()) {
                transfer (uri);
            }
        }

        private Gee.List<string> get_marked_row_uris () {
            var uri_list = new Gee.ArrayList<string> ();
            var row = list_box.get_first_child ();
            while (row != null) {
                if (row.get_data<Gtk.CheckButton> ("checkbutton").get_active ()) {
                    uri_list.add (current_uri.to_string (false) + "/" + row.get_data<string> ("name"));
                }
                row = row.get_next_sibling ();
            }
            return uri_list;
        }

        public void update_list (GLib.List<FileInfo> file_list) {
            clear_children (list_box);
            // Have to convert to gee list because glib list sort function is buggy
            // (it randomly removes items...)
            var gee_list = glib_to_gee<FileInfo> (file_list);
            alphabetical_order (gee_list);
            foreach (FileInfo file_info in gee_list) {
                if (file_info.get_name ().get_char (0) == '.') continue;
                list_box.append (new_row (file_info));
            }
        }

        private Gee.ArrayList<G> glib_to_gee<G> (GLib.List<G> list) {
            var gee_list = new Gee.ArrayList<G> ();
            foreach (G item in list) {
                gee_list.add (item);
            }
            return gee_list;
        }

        private void alphabetical_order (Gee.ArrayList<FileInfo> file_list) {
            file_list.sort ((a, b) => {
                if ((a.get_file_type () == FileType.DIRECTORY) &&
                    (b.get_file_type () == FileType.DIRECTORY)) {
                    return a.get_name ().collate (b.get_name ());
                }
                if (a.get_file_type () == FileType.DIRECTORY) {
                    return -1;
                }
                if (b.get_file_type () == FileType.DIRECTORY) {
                    return 1;
                }
                return a.get_name ().collate (b.get_name ());
            });
        }

        private Gtk.ListBoxRow new_row (FileInfo file_info) {
            var checkbox = new Gtk.CheckButton ();
            checkbox.toggled.connect (on_checkbutton_toggle);

            var icon = new Gtk.Image.from_gicon (file_info.get_icon ());

            var name = new Gtk.Label (file_info.get_name ());
            name.ellipsize = Pango.EllipsizeMode.END;
            name.halign = Gtk.Align.START;
            name.hexpand = true;

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                hexpand = true,
                margin_top = 6,
                margin_bottom = 6,
                margin_start = 12,
                margin_end = 12
            };
            row.append (checkbox);
            row.append (icon);
            row.append (name);

            if (file_info.get_file_type () == FileType.REGULAR) {
                var size = new Gtk.Label (bit_string_format (file_info.get_size ()));
                size.add_css_class ("dim-label");

                row.append (size);
            }

            var uri = new Soup.URI.with_base (current_uri, file_info.get_name ());

            var lbrow = new Gtk.ListBoxRow ();
            lbrow.hexpand = true;
            lbrow.tooltip_text = file_info.get_name ();
            lbrow.set_child (row);
            lbrow.set_data ("uri", uri);
            lbrow.set_data ("name", file_info.get_name ());
            lbrow.set_data ("type", file_info.get_file_type ());
            lbrow.set_data ("checkbutton", checkbox);

            var click_event = new Gtk.GestureClick ();
            click_event.set_button (3);
            lbrow.add_controller (click_event);

            var drag_event = new Gtk.DragSource ();

            var file = File.new_for_uri(uri.to_string (false));
            var drag_content = new Gdk.ContentProvider.for_value (file);
            drag_event.set_content (drag_content);
            lbrow.add_controller (drag_event);

            click_event.pressed.connect (() => {
                on_secondary_click(lbrow);
            });
            drag_event.drag_begin.connect (() => {
                on_drag_begin(drag_event, lbrow);
            });

            return lbrow;
        }

        private void on_checkbutton_toggle () {
            if (get_marked_row_uris ().size > 0) {
                path_bar.transfer_button_sensitive = true;
            } else {
                path_bar.transfer_button_sensitive = false;
            }
        }

        private void on_secondary_click (
            Gtk.Widget widget
        ) {
            var uri = widget.get_data<Soup.URI> ("uri");
            var type = widget.get_data<FileType> ("type");

            var model = new Menu ();
            var open_item = new MenuItem (_("Open"), null);

            var delete_item = new MenuItem (_("Delete"), null);
            string open_action = "win.open-local";
            string delete_action = "win.delete-local";

            if (type == FileType.DIRECTORY) {
                open_action = "win.navigate-local";
            }
            if (location == Location.REMOTE) {
                delete_action = "win.delete-remote";
                if (type == FileType.DIRECTORY) {
                    open_action = "win.navigate-remote";
                } else {
                    open_action = "win.open-remote";
                }
            }

            open_item.set_action_and_target_value(
                open_action,
                uri.to_string (false)
            );
            delete_item.set_action_and_target_value(
                delete_action,
                uri.to_string (false)
            );

            model.append_item (open_item);
            model.append_item (delete_item);

            var menu = new Gtk.PopoverMenu.from_model (model);
            menu.set_parent (widget);
            menu.popup ();
        }

        public void update_pathbar (Soup.URI uri) {
            current_uri = uri;
            path_bar.set_path (uri);
        }

        private void clear_children (Gtk.ListBox list) {
            var row = list.get_row_at_index (0);
            while (row != null) {
                list.remove (row);
                row = list.get_row_at_index (0);
            }
        }

        public void start_spinner () {
            stack.visible_child_name = "spinner";
        }

        public void stop_spinner () {
            stack.visible_child_name = "list";
        }

        private string bit_string_format (int64 bytes) {
            var floatbytes = (float) bytes;
            int i;
            for (i = 0; floatbytes >= 1000.0f || i > 6; i++) {
                floatbytes /= 1000.0f;
            }
            string[] measurement = { "bytes", "kB", "MB", "GB", "TB", "PB", "EB" };
            return "%.3g %s".printf (floatbytes, measurement [i]);
        }

        private void on_drag_begin (
            Gtk.DragSource source,
            Gtk.Widget row
        ) {
            var paintable = new Gtk.WidgetPaintable (row);
            source.set_icon (paintable, 0, 0);
        }

        private bool on_drag_drop (
            Gtk.DropTarget target,
            GLib.Value value,
            double x,
            double y
        ) {
            if (value.type () == typeof (Gdk.FileList)) {
                var files = ((Gdk.FileList)value).get_files();

                files.@foreach ((file) => {
                    file_dragged ((string) file.get_uri ());
                });
                return true;
            }
            return false;
        }

        private void navigate(Soup.URI uri) {
            var app = (Gtk.Application) Application.get_default ();
            var window = (Gtk.ApplicationWindow) app.get_active_window ();

            string action_name = "navigate-local";
            if (location == Location.REMOTE) {
                action_name = "navigate-remote";
            }

            var action = (SimpleAction) window.lookup_action (action_name);
            action.activate (uri.to_string (false));
        }

        private void open(Soup.URI uri) {
            var app = (Gtk.Application) Application.get_default ();
            var window = (Gtk.ApplicationWindow) app.get_active_window ();

            string action_name = "open-local";
            if (location == Location.REMOTE) {
                action_name = "open-remote";
            }

            var action = (SimpleAction) window.lookup_action (action_name);
            action.activate (uri.to_string (false));
        }
    }
}
