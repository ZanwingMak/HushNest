package com.hushnest.app;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import androidx.activity.result.ActivityResult;
import androidx.core.content.ContextCompat;
import com.getcapacitor.*;
import com.getcapacitor.annotation.*;
import org.json.JSONObject;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@CapacitorPlugin(name = "HushNest", permissions = { @Permission(alias = "notifications", strings = { Manifest.permission.POST_NOTIFICATIONS }) })
public class HushNestPlugin extends Plugin {
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService importer = Executors.newSingleThreadExecutor();
    private boolean importing;

    @PluginMethod public void snapshot(PluginCall call) {
        main.post(() -> { try { call.resolve(RestService.snapshot(getContext())); } catch (Exception e) { call.reject("snapshot-failed", e); } });
    }
    @PluginMethod public void command(PluginCall call) {
        String action = call.getString("action", "");
        if (action.equals("confirmRoute")) {
            android.media.AudioDeviceInfo d = HeadphoneRoute.candidate(getContext());
            if (d != null) RestService.prefs(getContext()).edit().putString("confirmedRoute", HeadphoneRoute.token(d)).apply();
            snapshot(call); return;
        }
        if (action.equals("clearRecords")) { RestService.prefs(getContext()).edit().putString("records", "[]").apply(); snapshot(call); return; }
        if (!java.util.Arrays.asList("start", "stop", "pause", "resume", "snooze", "volume", "preview").contains(action)) { call.reject("invalid-action"); return; }
        if (RestService.instance == null && !action.equals("start") && !action.equals("preview") && !action.equals("resume") && !action.equals("stop")) { call.reject("no-session"); return; }
        String commandID = UUID.randomUUID().toString();
        Intent intent = new Intent(getContext(), RestService.class);
        intent.putExtra("command", call.getData().toString()); intent.putExtra("commandID", commandID);
        main.post(() -> {
            try {
                ContextCompat.startForegroundService(getContext(), intent);
                resolveCommand(call, commandID, 0);
            } catch (Exception e) { call.reject("service-failed", e); }
        });
    }
    private void resolveCommand(PluginCall call, String id, int attempt) {
        if (RestService.lastCommand.equals(id)) {
            if (!RestService.lastError.isEmpty()) call.reject(RestService.lastError); else snapshot(call);
        } else if (attempt >= 60) call.reject("service-timeout");
        else main.postDelayed(() -> resolveCommand(call, id, attempt + 1), 50);
    }
    @PluginMethod public void requestNotifications(PluginCall call) {
        if (Build.VERSION.SDK_INT < 33 || getPermissionState("notifications") == PermissionState.GRANTED) { notificationResult(call); return; }
        requestPermissionForAlias("notifications", call, "notificationResult");
    }
    @PermissionCallback private void notificationResult(PluginCall call) {
        JSObject result = new JSObject(); result.put("granted", Build.VERSION.SDK_INT < 33 || getPermissionState("notifications") == PermissionState.GRANTED); call.resolve(result);
    }
    @PluginMethod public void listMedia(PluginCall call) {
        try { JSObject result = new JSObject(); result.put("items", NativeMedia.list(getContext())); call.resolve(result); }
        catch (Exception e) { call.reject("storage-failed", e); }
    }
    @PluginMethod public void importMedia(PluginCall call) {
        if (importing) { call.reject("import-in-progress"); return; }
        importing = true;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT); intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[]{"audio/*", "video/*"}); intent.addCategory(Intent.CATEGORY_OPENABLE);
        startActivityForResult(call, intent, "pickedMedia");
    }
    @ActivityCallback private void pickedMedia(PluginCall call, ActivityResult result) {
        if (call == null) { importing = false; return; }
        if (result.getResultCode() != Activity.RESULT_OK || result.getData() == null || result.getData().getData() == null) { importing = false; call.reject("cancelled"); return; }
        android.net.Uri uri = result.getData().getData();
        importer.execute(() -> {
            try { JSONObject item = NativeMedia.importFile(getContext(), uri); call.resolve(new JSObject(item.toString())); }
            catch (Exception e) { call.reject("media-format", e); }
            finally { importing = false; }
        });
    }
    @PluginMethod public void deleteMedia(PluginCall call) {
        try { if (RestService.instance != null && RestService.instance.session != null) throw new IllegalStateException("session-active"); NativeMedia.delete(getContext(), call.getString("id", "")); call.resolve(); }
        catch (Exception e) { call.reject("storage-failed", e); }
    }
    @Override protected void handleOnDestroy() { importer.shutdown(); super.handleOnDestroy(); }
}
