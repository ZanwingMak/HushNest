using System.Text.Json;
using NAudio.CoreAudioApi;
using NAudio.Wave;

// Playback is bound to one WASAPI endpoint. It never uses the default-device renderer.
static class Program
{
    private static readonly object Gate = new();
    private static WasapiOut? output;
    private static WaveStream? reader;
    private static LoopSource? loop;
    private static MMDevice? selected;
    private static string selectedToken = "";
    private static DateTime previewEnd = DateTime.MaxValue;
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private static string audioRoot = "", mediaRoot = "";

    record Route(bool Connected, bool Verified, string Name, string Token);
    static Route CurrentRoute()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            using var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            var form = Convert.ToInt32(device.Properties[PropertyKeys.PKEY_AudioEndpoint_FormFactor].Value);
            var headphones = device.State == DeviceState.Active && (form == 3 || form == 5);
            return new Route(headphones, headphones, device.FriendlyName, device.ID);
        }
        catch { return new Route(false, false, "", ""); }
    }
    static void Emit(object data)
    {
        lock (Console.Out) { Console.WriteLine(JsonSerializer.Serialize(data, Json)); Console.Out.Flush(); }
    }
    static void Stop()
    {
        var old = output; output = null;
        try { old?.Stop(); } catch { }
        old?.Dispose(); reader?.Dispose(); selected?.Dispose();
        reader = null; selected = null; loop = null; selectedToken = ""; previewEnd = DateTime.MaxValue;
    }
    static void Play(JsonElement data)
    {
        Stop(); var route = CurrentRoute(); if (!route.Connected) throw new InvalidOperationException("routeLost");
        var sound = data.GetProperty("sound").GetString() ?? "";
        var custom = sound.StartsWith("custom:"); string file;
        if (custom)
        {
            if (!Guid.TryParseExact(sound[7..], "D", out var id)) throw new InvalidOperationException("invalid-sound");
            file = Path.Combine(mediaRoot, id.ToString() + ".media");
        }
        else
        {
            var allowed = new HashSet<string>(["rain", "ocean", "stream", "forest", "fireplace", "night", "brown", "pink", "dawn", "bell", "orbit", "piano", "marimba", "harp", "bamboo", "aurora", "classic", "twinbell", "digital", "pulse", "beacon", "reveille"]);
            if (!allowed.Contains(sound)) throw new InvalidOperationException("invalid-sound");
            file = Path.Combine(audioRoot, sound + ".wav");
        }
        using var enumerator = new MMDeviceEnumerator(); selected = enumerator.GetDevice(route.Token); selectedToken = route.Token;
        reader = custom ? new MediaFoundationReader(file) : new WaveFileReader(file);
        var alarm = data.TryGetProperty("alarm", out var a) && a.GetBoolean();
        var preview = data.TryGetProperty("preview", out var p) && p.GetBoolean();
        loop = new LoopSource(reader, custom && alarm ? 60 : double.PositiveInfinity);
        loop.Volume = alarm && !preview ? 0 : (float)Math.Clamp(data.GetProperty("volume").GetDouble(), 0, 1);
        output = new WasapiOut(selected, AudioClientShareMode.Shared, true, 100);
        var current = output;
        current.PlaybackStopped += (_, e) => { if (e.Exception != null) Emit(new { eventType = "routeLost" }); };
        current.Init(loop.ToWaveProvider()); current.Play();
        previewEnd = preview ? DateTime.UtcNow.AddSeconds(2) : DateTime.MaxValue;
    }
    static void Check()
    {
        lock (Gate)
        {
            if (output == null) return;
            if (DateTime.UtcNow >= previewEnd) { Stop(); return; }
            var route = CurrentRoute();
            if (!route.Connected || route.Token != selectedToken || selected?.State != DeviceState.Active)
            {
                Stop(); Emit(new { eventType = "routeLost" });
            }
        }
    }
    static int Main(string[] args)
    {
        if (args.Length != 2) return 2;
        audioRoot = Path.GetFullPath(args[0]); mediaRoot = Path.GetFullPath(args[1]);
        using var timer = new Timer(_ => { try { Check(); } catch { lock (Gate) { Stop(); Emit(new { eventType = "routeLost" }); } } }, null, 100, 100);
        string? line;
        while ((line = Console.ReadLine()) != null)
        {
            long id = 0;
            try
            {
                using var message = JsonDocument.Parse(line); var data = message.RootElement; id = data.GetProperty("id").GetInt64();
                object? result = null;
                lock (Gate)
                {
                    switch (data.GetProperty("action").GetString())
                    {
                        case "route": result = CurrentRoute(); break;
                        case "inspect":
                            var media = data.GetProperty("sound").GetString() ?? "";
                            if (!media.StartsWith("custom:") || !Guid.TryParseExact(media[7..], "D", out var mediaId)) throw new InvalidOperationException("invalid-media");
                            using (var probe = new MediaFoundationReader(Path.Combine(mediaRoot, mediaId.ToString() + ".media")))
                            {
                                var duration = probe.TotalTime.TotalSeconds;
                                if (!double.IsFinite(duration) || duration <= 0 || probe.WaveFormat.Channels < 1) throw new InvalidOperationException("invalid-media");
                                result = new { seconds = duration };
                            }
                            break;
                        case "play": Play(data); break;
                        case "stop": Stop(); break;
                        case "volume": if (loop != null) loop.Volume = (float)Math.Clamp(data.GetProperty("value").GetDouble(), 0, 1); break;
                        default: throw new InvalidOperationException("invalid-action");
                    }
                }
                Emit(new { id, result, error = (string?)null });
            }
            catch (Exception e) { lock (Gate) Stop(); Emit(new { id, error = e.GetType().Name }); }
        }
        lock (Gate) Stop(); return 0;
    }
}

sealed class LoopSource : ISampleProvider
{
    private readonly WaveStream stream;
    private ISampleProvider source;
    private readonly long maxSamples;
    private long position;
    public volatile float Volume;
    public WaveFormat WaveFormat => source.WaveFormat;
    public LoopSource(WaveStream stream, double limit)
    {
        this.stream = stream; source = stream.ToSampleProvider();
        maxSamples = double.IsPositiveInfinity(limit) ? long.MaxValue : (long)(limit * source.WaveFormat.SampleRate * source.WaveFormat.Channels);
    }
    public int Read(float[] buffer, int offset, int count)
    {
        int total = 0, resets = 0;
        while (total < count)
        {
            int wanted = (int)Math.Min(count - total, maxSamples - position);
            int read = wanted > 0 ? source.Read(buffer, offset + total, wanted) : 0;
            if (read == 0)
            {
                if (++resets > 2) break;
                stream.Position = 0; source = stream.ToSampleProvider(); position = 0; continue;
            }
            resets = 0; total += read; position += read;
        }
        float volume = Volume; for (int i = 0; i < total; i++) buffer[offset + i] *= volume;
        return total;
    }
}
