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
    class PathBar : Gtk.Box {
        public bool transfer_button_sensitive { get; set; }

        private Soup.URI current_uri;

        public signal void navigate (Soup.URI uri);
        public signal void transfer ();

        public PathBar.from_uri (Soup.URI uri) {
            set_path (uri);
        }

        class construct {
            set_css_name ("button");
        }

        construct {
            add_css_class ("pathbar");
        }

        private string concat_until (string[] words, int n) {
            var result = "";
            for (int i = 0; (i < n + 1) && (i < words.length); i++) {
                result += words [i] + "/";
            }
            return result;
        }

        private void add_path_frag (string child, string path) {
            var button = new Gtk.Button ();

            if (path == "/") {
                button.icon_name = child;
            } else {
                var label = new Gtk.Label (child);
                label.ellipsize = Pango.EllipsizeMode.MIDDLE;

                button.tooltip_text = child;
                button.set_child (label);

                var sep = new PathBarSeparator ();
                append (sep);
            }

            button.add_css_class ("flat");
            button.add_css_class ("path-button");

            button.clicked.connect (() => {
                current_uri.set_path (path);
                navigate (current_uri);
            });
            append (button);
        }

        public void set_path (Soup.URI uri) {
            clear_path ();
            current_uri = uri;
            string transfer_icon_name;
            var scheme = uri.get_scheme ();
            switch (scheme) {
                case "file":
                    add_path_frag ("drive-harddisk-symbolic", "/");
                    transfer_icon_name = "document-send-symbolic";
                    break;
                case "ftp":
                case "sftp":
                default:
                    add_path_frag ("folder-remote-symbolic", "/");
                    transfer_icon_name = "document-save-symbolic";
                    break;
            }
            set_path_helper (uri.get_path ());

            var transfer_button = new Gtk.Button.from_icon_name (transfer_icon_name);
            transfer_button.halign = Gtk.Align.END;
            transfer_button.hexpand = true;
            transfer_button.sensitive = false;
            transfer_button.tooltip_text = _("Transfer");
            transfer_button.bind_property ("sensitive", this, "transfer-button-sensitive", GLib.BindingFlags.BIDIRECTIONAL);
            transfer_button.add_css_class ("flat");

            transfer_button.clicked.connect (() => transfer ());

            append (transfer_button);
        }

        private void set_path_helper (string path) {
            string[] directories = path.split ("/");
            for (int i = 0; i < directories.length; i++) {
                if (directories [i] != "") {
                    add_path_frag (directories [i], concat_until (directories, i));
                }
            }
        }

        private void clear_path () {
            var child = get_first_child ();
            while (child != null) {
                var item = child;
                child = child.get_next_sibling ();
                remove (item);
            }
            margin_top = 0;
            margin_bottom = 0;
            margin_start = 0;
            margin_end = 0;
        }
    }
}
