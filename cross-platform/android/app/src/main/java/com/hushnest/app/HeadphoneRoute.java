package com.hushnest.app;

import android.content.Context;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.os.Build;
import com.getcapacitor.JSObject;

final class HeadphoneRoute {
    static boolean eligible(AudioDeviceInfo d) {
        int t = d.getType();
        return t == AudioDeviceInfo.TYPE_WIRED_HEADPHONES || t == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
            t == AudioDeviceInfo.TYPE_USB_HEADSET || t == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            (Build.VERSION.SDK_INT >= 28 && t == AudioDeviceInfo.TYPE_HEARING_AID) ||
            (Build.VERSION.SDK_INT >= 31 && t == AudioDeviceInfo.TYPE_BLE_HEADSET);
    }
    static boolean wireless(AudioDeviceInfo d) {
        int t = d.getType(); return t == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            (Build.VERSION.SDK_INT >= 28 && t == AudioDeviceInfo.TYPE_HEARING_AID) ||
            (Build.VERSION.SDK_INT >= 31 && t == AudioDeviceInfo.TYPE_BLE_HEADSET);
    }
    static String token(AudioDeviceInfo d) { return d.getId() + ":" + d.getType(); }
    static AudioDeviceInfo candidate(Context context) {
        AudioManager audio = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        // Never guess between multiple outputs (e.g. a wired headset and a Bluetooth speaker).
        AudioDeviceInfo result = null;
        for (AudioDeviceInfo d : audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            if (eligible(d)) { if (result != null) return null; result = d; }
        }
        return result;
    }
    static AudioDeviceInfo approved(Context context) {
        AudioDeviceInfo d = candidate(context);
        if (d == null) return null;
        if (wireless(d) && !RestService.prefs(context).getString("confirmedRoute", "").equals(token(d))) return null;
        return d;
    }
    static JSObject snapshot(Context context) {
        AudioDeviceInfo d = candidate(context);
        JSObject result = new JSObject();
        result.put("connected", approved(context) != null);
        result.put("verified", d != null && !wireless(d));
        result.put("name", d == null ? "" : d.getProductName().toString());
        result.put("token", d == null ? "" : token(d));
        return result;
    }
}
