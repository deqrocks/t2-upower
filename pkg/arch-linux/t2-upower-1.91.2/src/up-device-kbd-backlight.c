/* -*- Mode: C; tab-width: 8; indent-tabs-mode: t; c-basic-offset: 8 -*-
 *
 * Copyright (C) 2025 Kate Hsuan <p.hsuan@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#include "config.h"

#include <glib.h>
#include <glib/gstdio.h>
#include <glib/gi18n-lib.h>
#include <glib-object.h>

#include "up-native.h"
#include "up-device-kbd-backlight.h"
#include "up-stats-item.h"

typedef struct
{
	UpDaemon	*daemon;
	GObject		*native;
} UpDeviceKbdBacklightPrivate;

static void up_device_kbd_backlight_initable_iface_init (GInitableIface *iface);

G_DEFINE_TYPE_EXTENDED (UpDeviceKbdBacklight, up_device_kbd_backlight, UP_TYPE_EXPORTED_KBD_BACKLIGHT_SKELETON, 0,
			G_IMPLEMENT_INTERFACE (G_TYPE_INITABLE,
					       up_device_kbd_backlight_initable_iface_init)
			G_ADD_PRIVATE (UpDeviceKbdBacklight))

enum {
	PROP_0,
	PROP_DAEMON,
	PROP_NATIVE,
	N_PROPS
};

/* Upower keeps the legacy keyboard backlight DBus API (/org/freedesktop/UPower/KbdBacklight/)
 * for backward compatibility.
 * The new API path is based on the legacy one and the suffix is the name of the keyboard
 * backlight device. For example, the path of the keyboard backlight device
 * "tpacpiookbd_backlight" is
 * "/org/freedesktop/UPower/KbdBacklight/tpacpiookbd_backlight".*/
#define UP_DEVICES_KBD_BACKLIGHT_DBUS_PATH "/org/freedesktop/UPower/KbdBacklight"
static GParamSpec *properties[N_PROPS];

/**
 * up_kbd_backlight_emit_change:
 **/
void
up_device_kbd_backlight_emit_change(UpDeviceKbdBacklight *kbd_backlight, int value, const char *source)
{
	up_exported_kbd_backlight_emit_brightness_changed (UP_EXPORTED_KBD_BACKLIGHT (kbd_backlight), value);
	up_exported_kbd_backlight_emit_brightness_changed_with_source (UP_EXPORTED_KBD_BACKLIGHT (kbd_backlight), value, source);
}


/**
 * up_kbd_backlight_get_brightness:
 *
 * Gets the current brightness
 **/
static gboolean
up_kbd_backlight_get_brightness (UpExportedKbdBacklight *skeleton,
				 GDBusMethodInvocation *invocation,
				 UpDeviceKbdBacklight *kbd_backlight)
{
	UpDeviceKbdBacklightClass *klass;
	gint brightness = 0;

	g_return_val_if_fail (UP_IS_DEVICE_KBD_BACKLIGHT (kbd_backlight), FALSE);

	klass = UP_DEVICE_KBD_BACKLIGHT_GET_CLASS (kbd_backlight);

	brightness = klass->get_brightness (kbd_backlight);

	if (brightness >= 0) {
		up_exported_kbd_backlight_complete_get_brightness (skeleton, invocation,
								   brightness);
	} else {
		g_dbus_method_invocation_return_error (invocation,
						       UP_DAEMON_ERROR, UP_DAEMON_ERROR_GENERAL,
						       "error reading brightness");
	}

	return TRUE;
}


/**
 * up_kbd_backlight_get_max_brightness:
 *
 * Gets the max brightness
 **/
static gboolean
up_kbd_backlight_get_max_brightness (UpExportedKbdBacklight *skeleton,
				     GDBusMethodInvocation *invocation,
				     UpDeviceKbdBacklight *kbd_backlight)
{
	UpDeviceKbdBacklightClass *klass;
	gint brightness = -1;

	g_return_val_if_fail (UP_IS_DEVICE_KBD_BACKLIGHT (kbd_backlight), FALSE);

	klass = UP_DEVICE_KBD_BACKLIGHT_GET_CLASS (kbd_backlight);

	if (klass->get_max_brightness != NULL)
		brightness = klass->get_max_brightness (kbd_backlight);

	if (brightness >= 0) {
		up_exported_kbd_backlight_complete_get_max_brightness (skeleton, invocation,
								       brightness);
	} else {
		g_dbus_method_invocation_return_error (invocation,
						       UP_DAEMON_ERROR, UP_DAEMON_ERROR_GENERAL,
						       "error reading max brightness");
	}

	return TRUE;
}


/**
 * up_kbd_backlight_set_brightness:
 *
 * Sets the kbd backlight LED brightness.
 **/
static gboolean
up_kbd_backlight_set_brightness (UpExportedKbdBacklight *skeleton,
				 GDBusMethodInvocation *invocation,
				 gint value,
				 UpDeviceKbdBacklight *kbd_backlight)
{
	UpDeviceKbdBacklightClass *klass;
	gboolean ret = FALSE;

	g_return_val_if_fail (UP_IS_DEVICE_KBD_BACKLIGHT (kbd_backlight), FALSE);

	klass = UP_DEVICE_KBD_BACKLIGHT_GET_CLASS (kbd_backlight);

	if (klass->set_brightness == NULL) {
		g_dbus_method_invocation_return_error (invocation,
						       UP_DAEMON_ERROR, UP_DAEMON_ERROR_GENERAL,
						       "setting brightness is unsupported");
		return TRUE;
	}
	ret = klass->set_brightness (kbd_backlight, value);

	if (ret) {
		up_exported_kbd_backlight_complete_set_brightness (skeleton, invocation);
		up_device_kbd_backlight_emit_change (kbd_backlight, value, "external");
	} else {
		g_dbus_method_invocation_return_error (invocation,
						       UP_DAEMON_ERROR, UP_DAEMON_ERROR_GENERAL,
						       "error writing brightness %d", value);
	}

	return TRUE;
}

GObject *
up_device_kbd_backlight_get_native (UpDeviceKbdBacklight *device)
{
	UpDeviceKbdBacklightPrivate *priv = up_device_kbd_backlight_get_instance_private (device);
	g_return_val_if_fail (UP_IS_DEVICE_KBD_BACKLIGHT (device), NULL);
	return priv->native;
}

static gchar *
up_device_kbd_backlight_compute_object_path (UpDeviceKbdBacklight *device)
{
	UpDeviceKbdBacklightPrivate *priv = up_device_kbd_backlight_get_instance_private (device);
	g_autofree gchar *basename = NULL;
	g_autofree gchar *id = NULL;
	gchar *object_path;
	const gchar *native_path;
	guint i;

	if (priv->native == NULL) {
		return g_build_filename (UP_DEVICES_KBD_BACKLIGHT_DBUS_PATH, "KbdBacklight", NULL);
	}

	native_path = up_exported_kbd_backlight_get_native_path (UP_EXPORTED_KBD_BACKLIGHT (device));
	basename = g_path_get_basename (native_path);
	id = g_strjoin ("_", basename, NULL);

	/* make DBUS valid path */
	for (i=0; id[i] != '\0'; i++) {
		if (id[i] == '-')
			id[i] = '_';
		if (id[i] == '.')
			id[i] = 'x';
		if (id[i] == ':')
			id[i] = 'o';
		if (id[i] == '@')
			id[i] = '_';
	}
	object_path = g_build_filename (UP_DEVICES_KBD_BACKLIGHT_DBUS_PATH, id, NULL);

	return object_path;
}

static void
up_device_kbd_backlight_export_skeleton (UpDeviceKbdBacklight *device,
				         const gchar *object_path)
{
	UpDeviceKbdBacklightPrivate *priv = up_device_kbd_backlight_get_instance_private (device);
	GError *error = NULL;

	g_dbus_interface_skeleton_export (G_DBUS_INTERFACE_SKELETON (device),
					  g_dbus_interface_skeleton_get_connection (G_DBUS_INTERFACE_SKELETON (priv->daemon)),
					  object_path,
					  &error);

	if (error != NULL) {
		g_critical ("error registering device on system bus: %s", error->message);
		g_error_free (error);
	}
}

gboolean
up_device_kbd_backlight_register (UpDeviceKbdBacklight *device)
{
	g_autofree char *computed_object_path = NULL;

	if (g_dbus_interface_skeleton_get_object_path (G_DBUS_INTERFACE_SKELETON (device)) != NULL)
		return FALSE;
	computed_object_path = up_device_kbd_backlight_compute_object_path (device);
	g_debug ("Exported Keyboard backlight with path %s", computed_object_path);
	up_device_kbd_backlight_export_skeleton (device, computed_object_path);
	return TRUE;
}

void
up_device_kbd_backlight_unregister (UpDeviceKbdBacklight *device)
{
	g_autofree char *object_path = NULL;

	object_path = g_strdup (g_dbus_interface_skeleton_get_object_path (G_DBUS_INTERFACE_SKELETON (device)));
	if (object_path != NULL) {
		g_dbus_interface_skeleton_unexport (G_DBUS_INTERFACE_SKELETON (device));
		g_debug ("Unexported UpDeviceKbdBacklight with path %s", object_path);
	}
}

const gchar *
up_device_kbd_backlight_get_object_path (UpDeviceKbdBacklight *device)
{
	g_return_val_if_fail (UP_IS_DEVICE_KBD_BACKLIGHT (device), NULL);
	return g_dbus_interface_skeleton_get_object_path (G_DBUS_INTERFACE_SKELETON (device));
}

static void
up_device_kbd_backlight_set_property (GObject      *object,
				      guint         prop_id,
				      const GValue *value,
				      GParamSpec   *pspec)
{
	UpDeviceKbdBacklight *device = UP_DEVICE_KBD_BACKLIGHT (object);
	UpDeviceKbdBacklightPrivate *priv = up_device_kbd_backlight_get_instance_private (device);

	switch (prop_id)
	{
	case PROP_DAEMON:
		priv->daemon = g_value_dup_object (value);
		break;

	case PROP_NATIVE:
		priv->native = g_value_dup_object (value);
		if (priv->native == NULL)
			g_warning ("KBD native is NULL");
		break;

	default:
		G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
	}
}

static void
up_device_kbd_backlight_get_property (GObject      *object,
				      guint         prop_id,
				      GValue       *value,
				      GParamSpec   *pspec)
{
	switch (prop_id)
	{
	default:
		G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
	}
}

static gboolean
up_device_kbd_backlight_initable_init (GInitable     *initable,
				       GCancellable  *cancellable,
				       GError       **error)
{
	UpDeviceKbdBacklight *device = UP_DEVICE_KBD_BACKLIGHT (initable);
	UpDeviceKbdBacklightPrivate *priv = up_device_kbd_backlight_get_instance_private (device);
	const gchar *native_path = NULL;
	UpDeviceKbdBacklightClass *klass = UP_DEVICE_KBD_BACKLIGHT_GET_CLASS (device);
	int ret;

	g_return_val_if_fail (UP_IS_DEVICE_KBD_BACKLIGHT (device), FALSE);

	if (priv->native) {
		native_path = up_native_get_native_path (priv->native);
		up_exported_kbd_backlight_set_native_path (UP_EXPORTED_KBD_BACKLIGHT (device), native_path);
	}

	/* coldplug source */
	if (klass->coldplug != NULL) {
		ret = klass->coldplug (device);
		if (!ret) {
			g_debug ("failed to coldplug %s", native_path);
			g_propagate_error (error, g_error_new (G_IO_ERROR, G_IO_ERROR_FAILED,
			                                       "Failed to coldplug %s", native_path));

			return FALSE;
		}
	}

	up_device_kbd_backlight_register (device);

	return TRUE;
}

static void
up_device_kbd_backlight_initable_iface_init (GInitableIface *iface)
{
	iface->init = up_device_kbd_backlight_initable_init;
}

/**
 * up_kbd_backlight_init:
 **/
static void
up_device_kbd_backlight_init (UpDeviceKbdBacklight *kbd_backlight)
{
	g_signal_connect (kbd_backlight, "handle-get-brightness",
			  G_CALLBACK (up_kbd_backlight_get_brightness), kbd_backlight);
	g_signal_connect (kbd_backlight, "handle-get-max-brightness",
			  G_CALLBACK (up_kbd_backlight_get_max_brightness), kbd_backlight);
	g_signal_connect (kbd_backlight, "handle-set-brightness",
			  G_CALLBACK (up_kbd_backlight_set_brightness), kbd_backlight);
}

/**
 * up_kbd_backlight_finalize:
 **/
static void
up_device_kbd_backlight_finalize (GObject *object)
{
	g_return_if_fail (object != NULL);
	g_return_if_fail (UP_IS_DEVICE_KBD_BACKLIGHT (object));

	G_OBJECT_CLASS (up_device_kbd_backlight_parent_class)->finalize (object);
}

static void
up_device_kbd_backlight_class_init (UpDeviceKbdBacklightClass *klass)
{
	GObjectClass *object_class = G_OBJECT_CLASS (klass);

	object_class->finalize = up_device_kbd_backlight_finalize;

	object_class->set_property = up_device_kbd_backlight_set_property;
	object_class->get_property = up_device_kbd_backlight_get_property;

	properties[PROP_DAEMON] =
		g_param_spec_object ("daemon",
				     "UpDaemon",
				     "UpDaemon reference",
				     UP_TYPE_DAEMON,
				     G_PARAM_STATIC_STRINGS | G_PARAM_WRITABLE | G_PARAM_CONSTRUCT_ONLY);

	properties[PROP_NATIVE] =
		g_param_spec_object ("native",
				     "Native",
				     "Native Object",
				     G_TYPE_OBJECT,
				     G_PARAM_STATIC_STRINGS | G_PARAM_WRITABLE | G_PARAM_CONSTRUCT_ONLY);

	g_object_class_install_properties (object_class, N_PROPS, properties);
}

/**
 * up_kbd_backlight_new:
 **/
UpDeviceKbdBacklight *
up_device_kbd_backlight_new (UpDaemon *daemon, GObject *native)
{
	return UP_DEVICE_KBD_BACKLIGHT (g_object_new (UP_TYPE_DEVICE_KBD_BACKLIGHT,
					"daemon", daemon,
					"native", native,
					NULL));
}
