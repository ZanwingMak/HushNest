package com.hushnest.app;

import android.content.Context;
import android.database.Cursor;
import android.media.*;
import android.net.Uri;
import android.provider.OpenableColumns;
import org.json.*;
import java.io.*;
import java.nio.ByteBuffer;
import java.util.UUID;

final class NativeMedia {
    static synchronized JSONArray list(Context context) throws JSONException { return new JSONArray(RestService.prefs(context).getString("media", "[]")); }
    static File file(Context context, String id) throws IOException {
        if (!id.matches("[0-9a-f-]{36}")) throw new IOException("invalid-id");
        File dir = new File(context.getFilesDir(), "media");
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("storage-failed");
        return new File(dir, id + ".media");
    }
    static synchronized void delete(Context context, String id) throws Exception {
        File target = file(context, id);
        if (target.exists() && !target.delete()) throw new IOException("delete-failed");
        JSONArray items = list(context), next = new JSONArray();
        for (int i = 0; i < items.length(); i++) if (!items.getJSONObject(i).getString("id").equals(id)) next.put(items.get(i));
        if (!RestService.prefs(context).edit().putString("media", next.toString()).commit()) throw new IOException("storage-failed");
    }
    static JSONObject importFile(Context context, Uri uri) throws Exception {
        if (list(context).length() >= 20) throw new IOException("media-count");
        String name = "Audio";
        try (Cursor cursor = context.getContentResolver().query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) name = cursor.getString(0);
        }
        String id = UUID.randomUUID().toString(); File temporary = new File(context.getCacheDir(), id + ".input"); File target = file(context, id);
        try {
            long size = 0;
            try (InputStream input = context.getContentResolver().openInputStream(uri); OutputStream output = new FileOutputStream(temporary)) {
                if (input == null) throw new IOException("media-format");
                byte[] bytes = new byte[65536]; int n;
                while ((n = input.read(bytes)) != -1) { size += n; if (size > 200L * 1024 * 1024) throw new IOException("media-size"); output.write(bytes, 0, n); }
            }
            if (size == 0) throw new IOException("media-size");
            MediaMetadataRetriever meta = new MediaMetadataRetriever(); long duration; boolean video;
            try {
                meta.setDataSource(temporary.getPath());
                duration = Long.parseLong(meta.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION));
                video = "yes".equals(meta.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO));
                if (!"yes".equals(meta.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO))) throw new IOException("no-audio");
            } finally { meta.release(); }
            if (duration <= 0 || duration > 7200000) throw new IOException("media-duration");
            if (video) extractAudio(temporary, target); else if (!temporary.renameTo(target)) {
                try (InputStream in = new FileInputStream(temporary); OutputStream out = new FileOutputStream(target)) { byte[] b = new byte[65536]; int n; while ((n = in.read(b)) != -1) out.write(b, 0, n); }
            }
            JSONObject item = new JSONObject().put("id", id).put("name", name == null ? "Audio" : name.substring(0, Math.min(200, name.length()))).put("duration", duration / 1000.0).put("size", target.length());
            synchronized (NativeMedia.class) {
                JSONArray items = list(context); if (items.length() >= 20) throw new IOException("media-count");
                items.put(item); if (!RestService.prefs(context).edit().putString("media", items.toString()).commit()) throw new IOException("storage-failed");
            }
            return item;
        } catch (Exception error) { target.delete(); throw error; }
        finally { temporary.delete(); }
    }
    private static void extractAudio(File input, File output) throws Exception {
        MediaExtractor extractor = new MediaExtractor(); MediaMuxer muxer = null; boolean started = false;
        try {
            extractor.setDataSource(input.getPath()); int audioTrack = -1;
            for (int i = 0; i < extractor.getTrackCount(); i++) if (extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith("audio/")) { audioTrack = i; break; }
            if (audioTrack < 0) throw new IOException("no-audio");
            extractor.selectTrack(audioTrack); MediaFormat format = extractor.getTrackFormat(audioTrack);
            muxer = new MediaMuxer(output.getPath(), MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            int track = muxer.addTrack(format); muxer.start(); started = true;
            int capacity = Math.max(1024 * 1024, format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE) ? format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) : 0);
            if (capacity > 16 * 1024 * 1024) throw new IOException("media-format");
            ByteBuffer data = ByteBuffer.allocate(capacity); MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            while (true) {
                data.clear(); int size = extractor.readSampleData(data, 0); if (size < 0) break;
                int sampleFlags = extractor.getSampleFlags();
                if ((sampleFlags & MediaExtractor.SAMPLE_FLAG_ENCRYPTED) != 0) throw new IOException("protected-media");
                int codecFlags = (sampleFlags & MediaExtractor.SAMPLE_FLAG_SYNC) != 0 ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0;
                if ((sampleFlags & MediaExtractor.SAMPLE_FLAG_PARTIAL_FRAME) != 0) codecFlags |= MediaCodec.BUFFER_FLAG_PARTIAL_FRAME;
                info.set(0, size, extractor.getSampleTime(), codecFlags); muxer.writeSampleData(track, data, info); extractor.advance();
            }
        } finally { extractor.release(); if (muxer != null) { try { if (started) muxer.stop(); } finally { muxer.release(); } } }
    }
}
