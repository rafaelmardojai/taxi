valac \
Shift.vala \
GUI.vala \
Widgets/PathBar.vala \
Widgets/FilePane.vala \
Widgets/ConnectDialog.vala \
--target-glib=2.36 --pkg gtk+-3.0 --pkg granite --pkg posix --output app
./app
