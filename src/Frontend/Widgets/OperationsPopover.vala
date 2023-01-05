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

    class OperationsPopover : Gtk.Popover {

        Gtk.Box box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        Gee.Map<IOperationInfo, Gtk.Box> operation_map
            = new Gee.HashMap <IOperationInfo, Gtk.Box> ();
        Gtk.Label placeholder;

        public signal void operations_pending ();
        public signal void operations_finished ();

        public OperationsPopover (Gtk.Widget widget) {
            set_parent (widget);
            margin_top = 12;
            margin_bottom = 12;
            margin_start = 12;
            margin_end = 12;
            placeholder = new Gtk.Label (_("No file operations are in progress"));
            set_child (box);
            build ();
        }

        private void build () {
            box.append (placeholder);
        }

        public void add_operation (IOperationInfo operation) {
            if (box.get_first_child () == placeholder) {
                box.remove (placeholder);
                operations_pending ();
            }
            var row = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            operation_map.set (operation, row);

            row.append (new Gtk.Label (operation.get_file_name ()));

            operation.get_file_icon.begin ((obj, res) => {
                row.append (
                    new Gtk.Image.from_gicon (operation.get_file_icon.end (res))
                );
            });

            var cancel = new Gtk.Button.from_icon_name ("process-stop-symbolic");
            cancel.clicked.connect (() => {
                operation.cancel ();
            });
            row.append (cancel);

            box.append (row);
        }

        public void remove_operation (IOperationInfo operation) {
            var row = operation_map.get (operation);
            box.remove (row);
            operation_map.unset (operation);
            if (operation_map.size == 0) {
                operations_finished ();
                box.append (placeholder);
            }
        }
    }
}
