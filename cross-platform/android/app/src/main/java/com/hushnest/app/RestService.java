package com.hushnest.app;

import android.app.*;
import android.content.*;
import android.content.pm.ServiceInfo;
import android.media.*;
import android.os.*;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;
import androidx.core.content.ContextCompat;
import com.getcapacitor.JSObject;
import org.json.*;
import java.io.File;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/** The native service, rather than WebView timers, owns Android sessions and audio. */
public class RestService extends Service {
    static RestService instance;
    static String lastCommand = "", lastError = "";
    JSONObject session;
    private JSONObject config = new JSONObject();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private AudioManager audio;
    private MediaPlayer player;
    private AudioFocusRequest focus;
    private PowerManager.WakeLock wake;
    private String playbackKey = "", outputToken = "";
    private boolean prepared, routeValidated, interrupted, stopping;
    private long lastSave, lastNotification, preparedAt, previewUntil;
    private float previewVolume;
    private final Runnable pulse = new Runnable() { public void run() { try { tick(); } catch (Exception e) { fail("audioError"); } if (!stopping) handler.postDelayed(this, 200); } };
    private final AudioDeviceCallback devices = new AudioDeviceCallback() {
        @Override public void onAudioDevicesRemoved(AudioDeviceInfo[] removed) {
            for (AudioDeviceInfo d : removed) if (HeadphoneRoute.token(d).equals(outputToken)) {
                prefs(RestService.this).edit().remove("confirmedRoute").apply(); fail("routeLost"); break;
            }
        }
    };
    private final BroadcastReceiver noisy = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { fail("routeLost"); }
    };
    static SharedPreferences prefs(Context context) { return context.getSharedPreferences("hushnest-native", MODE_PRIVATE); }
    private static JSONObject storedSession(Context context) {
        try {
            String raw = prefs(context).getString("session", "null"); if (raw.equals("null")) return null;
            JSONObject result = new JSONObject(raw);
            if (!result.optString("phase").equals("paused")) result.put("phase", "blocked").put("reason", "restored");
            result.put("restingSince", JSONObject.NULL); return result;
        } catch (JSONException e) { return null; }
    }
    static JSObject snapshot(Context context) throws JSONException {
        JSObject result = new JSObject();
        result.put("session", instance == null ? (storedSession(context) == null ? JSONObject.NULL : storedSession(context)) : instance.session == null ? JSONObject.NULL : new JSONObject(instance.session.toString()));
        result.put("route", HeadphoneRoute.snapshot(context));
        result.put("records", new JSONArray(prefs(context).getString("records", "[]"))); return result;
    }
    @Override public void onCreate() {
        super.onCreate(); instance = this; session = storedSession(this);
        try { config = new JSONObject(prefs(this).getString("config", "{}")); } catch (JSONException ignored) { }
        audio = (AudioManager) getSystemService(AUDIO_SERVICE);
        wake = ((PowerManager) getSystemService(POWER_SERVICE)).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "HushNest:Rest");
        wake.setReferenceCounted(false);
        audio.registerAudioDeviceCallback(devices, handler);
        ContextCompat.registerReceiver(this, noisy, new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), ContextCompat.RECEIVER_EXPORTED);
        NotificationChannel channel = new NotificationChannel("hushnest-rest-v1", "HushNest · Rest", NotificationManager.IMPORTANCE_LOW);
        channel.setSound(null, null); channel.enableVibration(false); channel.setShowBadge(false);
        getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) { stopSelf(); return START_NOT_STICKY; }
        try {
            int type = Build.VERSION.SDK_INT >= 34 ? ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE : 0;
            ServiceCompat.startForeground(this, 41, notification(), type);
            String payload = intent.getStringExtra("command"); String commandID = intent.getStringExtra("commandID");
            if (payload == null) {
                String action = intent.getAction();
                if ("stop".equals(action)) finish(false); else if ("snooze".equals(action)) apply(new JSONObject().put("action", "snooze"));
            } else {
                lastError = "";
                try { apply(new JSONObject(payload)); } catch (Exception error) { lastError = error.getMessage() == null ? "audioError" : error.getMessage(); fail("audioError"); }
                lastCommand = commandID == null ? "" : commandID;
            }
            handler.removeCallbacks(pulse); if (!stopping) handler.post(pulse);
        } catch (Exception error) { lastError = "service-failed"; lastCommand = intent.getStringExtra("commandID"); stopSelf(); }
        return START_NOT_STICKY;
    }
    private void apply(JSONObject data) throws Exception {
        String action = data.optString("action"); long now = System.currentTimeMillis();
        if (data.has("preferences")) { config = data.getJSONObject("preferences"); prefs(this).edit().putString("config", config.toString()).apply(); }
        if (action.equals("preview")) {
            if (session != null) throw new IllegalStateException("session-active");
            if (HeadphoneRoute.approved(this) == null) throw new IllegalStateException("routeLost");
            previewUntil = now + 2000; previewVolume = (float) Math.min(0.18, Math.max(0.01, data.optDouble("volume", 0.1)));
            requestFocus(); play(data.getString("sound"), false); return;
        }
        if (action.equals("start")) {
            if (session != null) throw new IllegalStateException("session-active");
            if (HeadphoneRoute.approved(this) == null) throw new IllegalStateException("routeLost");
            JSONObject proposed = data.getJSONObject("session");
            int duration = Math.min(43200, Math.max(1, proposed.optInt("duration", 1800)));
            session = new JSONObject().put("id", java.util.UUID.randomUUID().toString()).put("startedAt", now).put("deadline", now + duration * 1000L)
                .put("duration", duration).put("phase", "resting").put("pausedRemaining", JSONObject.NULL).put("snoozeCount", 0)
                .put("accumulatedRest", 0).put("restingSince", now).put("reason", JSONObject.NULL);
            requestFocus(); holdWake();
        } else if (action.equals("stop")) {
            finish(session != null && (phase().equals("ringing") || session.isNull("pausedRemaining") && now >= session.optLong("deadline"))); return;
        } else if (session == null) throw new IllegalStateException("no-session");
        else if (action.equals("pause") && phase().equals("resting")) {
            settle(now); session.put("pausedRemaining", Math.max(0, (session.getLong("deadline") - now) / 1000.0)).put("phase", "paused");
            stopAudio(); releaseWake(); abandonFocus();
        } else if (action.equals("resume") && (phase().equals("paused") || phase().equals("blocked"))) {
            if (HeadphoneRoute.approved(this) == null) throw new IllegalStateException("routeLost");
            if (!session.isNull("pausedRemaining")) session.put("deadline", now + Math.round(session.getDouble("pausedRemaining") * 1000));
            session.put("pausedRemaining", JSONObject.NULL).put("reason", JSONObject.NULL).put("phase", now >= session.getLong("deadline") ? "ringing" : "resting")
                .put("restingSince", now < session.getLong("deadline") ? now : JSONObject.NULL);
            interrupted = false; outputToken = ""; requestFocus(); holdWake();
        } else if (action.equals("snooze") && phase().equals("ringing")) {
            if (HeadphoneRoute.approved(this) == null) throw new IllegalStateException("routeLost");
            int duration = Math.max(1, Math.min(30, config.optInt("snoozeMinutes", 5))) * 60;
            session.put("duration", duration).put("deadline", now + duration * 1000L).put("phase", "resting").put("restingSince", now)
                .put("snoozeCount", session.optInt("snoozeCount") + 1); stopAudio(); holdWake();
        }
        persist(); tick();
    }
    private String phase() { return session == null ? "" : session.optString("phase"); }
    private void settle(long now) throws JSONException {
        if (session == null) return;
        double seconds = session.optDouble("accumulatedRest", 0);
        if (!session.isNull("restingSince")) seconds += Math.max(0, (Math.min(now, session.getLong("deadline")) - session.getLong("restingSince")) / 1000.0);
        session.put("accumulatedRest", seconds).put("restingSince", JSONObject.NULL);
    }
    private void tick() throws Exception {
        long now = System.currentTimeMillis();
        if (previewUntil > 0) {
            if (now >= previewUntil) { previewUntil = 0; stopAudio(); if (session == null) { shutdown(); return; } }
            else { validateAndVolume(previewVolume); return; }
        }
        if (session == null) { shutdown(); return; }
        if (phase().equals("resting") && now >= session.getLong("deadline")) { settle(now); session.put("phase", "ringing"); persist(); }
        if ((phase().equals("ringing") || phase().equals("blocked")) && session.isNull("pausedRemaining") && !config.optBoolean("repeatAlarm") && now >= session.getLong("deadline") + 180000) { finish(true); return; }
        if (phase().equals("resting") || phase().equals("ringing")) {
            AudioDeviceInfo route = HeadphoneRoute.approved(this);
            if (route == null || !outputToken.isEmpty() && !HeadphoneRoute.token(route).equals(outputToken)) { fail("routeLost"); return; }
            boolean alarm = phase().equals("ringing"); String sound = config.optString(alarm ? "alarmSound" : "sleepSound", alarm ? "dawn" : "rain");
            String key = phase() + ":" + sound;
            if (!key.equals(playbackKey)) {
                stopAudio(); if (!sound.equals("none")) play(sound, alarm); playbackKey = key;
            }
            float volume = (float) Math.min(alarm ? 1 : 0.6, Math.max(alarm ? 0.05 : 0.01, config.optDouble(alarm ? "alarmVolume" : "sleepVolume", alarm ? 0.55 : 0.18)));
            if (alarm) volume *= (float) Math.min(1, Math.max(0.01, (now - session.getLong("deadline")) / 15000.0));
            validateAndVolume(volume);
            if (alarm && config.optBoolean("vibration") && now / 1000 % 3 == 0 && routeValidated) {
                Vibrator vibrator = (Vibrator) getSystemService(VIBRATOR_SERVICE); if (vibrator != null && vibrator.hasVibrator()) vibrator.vibrate(VibrationEffect.createOneShot(100, VibrationEffect.DEFAULT_AMPLITUDE));
            }
            if (alarm && sound.startsWith("custom:") && player != null && prepared && player.getCurrentPosition() >= 60000) player.seekTo(0);
        }
        if (now - lastSave >= 10000) {
            if (phase().equals("resting")) { settle(now); session.put("restingSince", now); }
            persist(); lastSave = now;
        }
        if (now - lastNotification >= 10000) { getSystemService(NotificationManager.class).notify(41, notification()); lastNotification = now; }
    }
    private void requestFocus() throws Exception {
        if (focus != null) return;
        focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
            .setOnAudioFocusChangeListener(change -> {
                if (change == AudioManager.AUDIOFOCUS_GAIN && interrupted && session != null && HeadphoneRoute.approved(this) != null) {
                    interrupted = false;
                    try { session.put("phase", System.currentTimeMillis() >= session.getLong("deadline") ? "ringing" : "resting").put("reason", JSONObject.NULL);
                        if (phase().equals("resting")) session.put("restingSince", System.currentTimeMillis()); holdWake(); persist(); }
                    catch (Exception e) { fail("audioError"); }
                } else if (change < 0) {
                    fail("audioError"); interrupted = change != AudioManager.AUDIOFOCUS_LOSS;
                    if (change == AudioManager.AUDIOFOCUS_LOSS) abandonFocus();
                }
            }, handler).build();
        if (audio.requestAudioFocus(focus) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { focus = null; throw new IllegalStateException("audioError"); }
    }
    private void abandonFocus() { if (focus != null) { audio.abandonAudioFocusRequest(focus); focus = null; } }
    private void play(String sound, boolean alarm) throws Exception {
        AudioDeviceInfo target = HeadphoneRoute.approved(this); if (target == null) throw new IllegalStateException("routeLost");
        stopAudio(); outputToken = HeadphoneRoute.token(target);
        MediaPlayer next = new MediaPlayer(); player = next;
        next.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build());
        next.setVolume(0, 0); next.setLooping(true);
        if (sound.startsWith("custom:")) {
            File file = NativeMedia.file(this, sound.substring(7)); if (!file.isFile()) throw new IllegalStateException("missing-media"); next.setDataSource(file.getPath());
        } else {
            Set<String> allowed = new HashSet<>(Arrays.asList("rain", "ocean", "stream", "forest", "fireplace", "night", "brown", "pink", "dawn", "bell", "orbit", "piano", "marimba", "harp", "bamboo", "aurora", "classic", "twinbell", "digital", "pulse", "beacon", "reveille"));
            if (!allowed.contains(sound)) throw new IllegalArgumentException("invalid-sound");
            android.content.res.AssetFileDescriptor fd = getAssets().openFd("public/audio/" + sound + ".wav");
            try { next.setDataSource(fd.getFileDescriptor(), fd.getStartOffset(), fd.getLength()); } finally { fd.close(); }
        }
        if (!next.setPreferredDevice(target)) throw new IllegalStateException("routeLost");
        next.addOnRoutingChangedListener(routing -> { if (player == next && prepared) { AudioDeviceInfo actual = next.getRoutedDevice(); if (actual != null && !HeadphoneRoute.token(actual).equals(outputToken)) fail("routeLost"); } }, handler);
        next.setOnPreparedListener(ready -> {
            if (player != next) return;
            AudioDeviceInfo current = HeadphoneRoute.approved(this);
            if (current == null || !HeadphoneRoute.token(current).equals(outputToken)) { fail("routeLost"); return; }
            try { prepared = true; preparedAt = System.currentTimeMillis(); ready.start(); }
            catch (Exception error) { fail("audioError"); }
        });
        next.setOnErrorListener((mp, what, extra) -> { if (player == next) fail("audioError"); return true; });
        next.prepareAsync();
    }
    private void validateAndVolume(float volume) {
        if (player == null || !prepared) return;
        AudioDeviceInfo actual = player.getRoutedDevice(); AudioDeviceInfo approved = HeadphoneRoute.approved(this);
        if (actual != null && approved != null && HeadphoneRoute.token(actual).equals(outputToken) && HeadphoneRoute.token(approved).equals(outputToken)) { routeValidated = true; player.setVolume(volume, volume); }
        else { player.setVolume(0, 0); if (System.currentTimeMillis() - preparedAt > 1000) fail("routeLost"); }
    }
    private void stopAudio() {
        MediaPlayer old = player; player = null; prepared = false; routeValidated = false; playbackKey = "";
        if (old != null) { try { old.setVolume(0, 0); old.release(); } catch (Exception ignored) { } }
        Vibrator vibrator = (Vibrator) getSystemService(VIBRATOR_SERVICE); if (vibrator != null) vibrator.cancel();
    }
    private void fail(String reason) {
        stopAudio(); previewUntil = 0;
        if (session != null && !phase().equals("paused")) {
            try { settle(System.currentTimeMillis()); session.put("phase", "blocked").put("reason", reason); persist(); getSystemService(NotificationManager.class).notify(41, notification()); }
            catch (Exception ignored) { }
        }
        if (session == null) shutdown();
    }
    private void persist() { prefs(this).edit().putString("session", session == null ? "null" : session.toString()).apply(); }
    private void finish(boolean completed) throws JSONException {
        if (session != null) {
            long now = System.currentTimeMillis(); settle(now);
            JSONObject record = new JSONObject().put("id", session.getString("id")).put("startedAt", session.getLong("startedAt")).put("endedAt", now)
                .put("seconds", Math.floor(session.optDouble("accumulatedRest"))).put("completed", completed).put("sound", config.optString("sleepSound", "rain"));
            JSONArray old = new JSONArray(prefs(this).getString("records", "[]")), next = new JSONArray(); next.put(record);
            for (int i = 0; i < old.length() && next.length() < 365; i++) if (!old.getJSONObject(i).optString("id").equals(record.getString("id"))) next.put(old.get(i));
            prefs(this).edit().putString("records", next.toString()).apply();
        }
        session = null; persist(); shutdown();
    }
    private void holdWake() { if (!wake.isHeld()) wake.acquire(13L * 60 * 60 * 1000); }
    private void releaseWake() { if (wake.isHeld()) wake.release(); }
    private PendingIntent action(String name) {
        return PendingIntent.getService(this, name.hashCode(), new Intent(this, RestService.class).setAction(name), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
    private Notification notification() {
        PendingIntent open = PendingIntent.getActivity(this, 1, new Intent(this, MainActivity.class), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        String language = config.optString("language", "en");
        int index = Math.max(0, Arrays.asList("zh-Hans", "zh-Hant", "en", "ja", "ko", "es").indexOf(language));
        String title = phase().equals("ringing") ? new String[]{"时间到了", "時間到了", "Time to wake up", "起きる時間です", "일어날 시간이에요", "Hora de despertar"}[index]
            : phase().equals("blocked") ? new String[]{"提醒已中断", "提醒已中斷", "Rest interrupted", "休憩が中断されました", "휴식이 중단되었어요", "Descanso interrumpido"}[index]
            : phase().equals("paused") ? new String[]{"休息已暂停", "休息已暫停", "Rest paused", "休憩を一時停止", "휴식 일시 정지", "Descanso en pausa"}[index]
            : new String[]{"好好休息", "好好休息", "Rest quietly", "ゆっくり休んで", "편히 쉬세요", "Descansa en calma"}[index];
        long remaining = session == null ? 0 : Math.max(0, (session.optLong("deadline") - System.currentTimeMillis()) / 1000);
        String text = session == null ? "HushNest" : String.format(java.util.Locale.ROOT, "%02d:%02d · HushNest", remaining / 60, remaining % 60);
        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, "hushnest-rest-v1").setSmallIcon(R.drawable.ic_rest_notification)
            .setContentTitle(title).setContentText(text).setContentIntent(open).setOngoing(true).setSilent(true).setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH).addAction(0, new String[]{"结束休息", "結束休息", "End rest", "休憩を終了", "휴식 종료", "Terminar descanso"}[index], action("stop"));
        if (phase().equals("ringing")) builder.addAction(0, new String[]{"稍后提醒", "稍後提醒", "Snooze", "スヌーズ", "다시 알림", "Posponer"}[index], action("snooze"));
        return builder.build();
    }
    private void shutdown() { stopping = true; handler.removeCallbacks(pulse); stopAudio(); releaseWake(); abandonFocus(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); }
    @Override public void onDestroy() {
        stopping = true; handler.removeCallbacksAndMessages(null); stopAudio(); releaseWake(); abandonFocus();
        audio.unregisterAudioDeviceCallback(devices); unregisterReceiver(noisy);
        if (session != null) { try { settle(System.currentTimeMillis()); session.put("phase", "blocked").put("reason", "restored"); persist(); } catch (Exception ignored) { } }
        instance = null; super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
