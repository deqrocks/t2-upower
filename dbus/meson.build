
upowerd_dbus_interfaces = [
    [ 'daemon', 'org.freedesktop.UPower', 'Daemon' ],
    [ 'device', 'org.freedesktop.UPower.Device', 'Device' ],
    [ 'kbd-backlight', 'org.freedesktop.UPower.KbdBacklight', 'KbdBacklight' ],
]

gdbus_codegen = find_program('gdbus-codegen', required: false)
if not gdbus_codegen.found()
    error('gdbus-codegen is required to generate the D-Bus sources. Install the GLib code generator package for your distro.')
endif

upowerd_dbus_headers = []
upowerd_dbus_sources = []
foreach interface: upowerd_dbus_interfaces
    xml = interface[1] + '.xml'
    target_name = 'up-' + interface[0] + '-generated'
    t = custom_target(target_name,
        input: xml,
        output: [target_name + '.c', target_name + '.h'],
        command: [
            gdbus_codegen,
            '--c-generate-autocleanup', 'all',
            '--c-namespace', 'Up',
            '--annotate', interface[1], 'org.gtk.GDBus.C.Name', 'Exported' + interface[2],
            '--generate-c-code', '@OUTDIR@/' + target_name,
            '@INPUT@',
        ],
    )
    upowerd_dbus_sources += t[0]
    upowerd_dbus_headers += t[1]

    install_data(xml,
        install_dir: dbusdir / 'interfaces',
    )
endforeach


upowerd_dbus = static_library('libupower-dbus',
    sources: upowerd_dbus_sources + upowerd_dbus_headers,
    dependencies: [ gobject_dep, gio_dep, gio_unix_dep ],
)

upowerd_dbus_dep = declare_dependency(
    link_with: upowerd_dbus,
    include_directories: [ '.' ],
    sources: upowerd_dbus_headers,
    dependencies: [ gio_unix_dep ]
)
