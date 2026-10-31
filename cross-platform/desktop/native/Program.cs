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
    private static string confirmedToken = "", observedToken = "";
    private static DateTime previewEnd = DateTime.MaxValue;
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private static string audioRoot = "", mediaRoot = "";
    private static readonly HashSet<string> Sounds = new(["rain", "ocean", "stream", "forest", "fireplace", "night", "brown", "pink", "dawn", "bell", "orbit", "piano", "marimba", "harp", "bamboo", "aurora", "classic", "twinbell", "digital", "pulse", "beacon", "reveille"]);

    static WaveStream OpenSound(string sound)
    {
        if (sound.StartsWith("custom:"))
        {
            if (!Guid.TryParseExact(sound[7..], "D", out var id)) throw new InvalidOperationException("invalid-sound");
            return new MediaFoundationReader(Path.Combine(mediaRoot, id.ToString() + ".media"));
        }
        if (!Sounds.Contains(sound)) throw new InvalidOperationException("invalid-sound");
        return new WaveFileReader(Path.Combine(audioRoot, sound + ".wav"));
    }
    static double Number(JsonElement data, string key, double fallback, double max)
    {
        var value = data.TryGetProperty(key, out var field) ? field.GetDouble() : fallback;
        if (!double.IsFinite(value) || value < 0 || value > max) throw new InvalidOperationException("invalid-number");
        return value;
    }
    static object Inspect(JsonElement data)
    {
        using var stream = OpenSound(data.GetProperty("sound").GetString() ?? "");
        var duration = stream.TotalTime.TotalSeconds;
        if (!double.IsFinite(duration) || duration <= 0 || stream.WaveFormat.Channels < 1) throw new InvalidOperationException("invalid-media");
        var start = Number(data, "startSeconds", 0, 7200);
        var seconds = Number(data, "sampleSeconds", 0, 4);
        var source = new LoopSource(stream, double.PositiveInfinity, start) { Volume = 1 };
        var wanted = seconds > 0 ? (long)(seconds * source.WaveFormat.SampleRate * source.WaveFormat.Channels) : 2048;
        var buffer = new float[4096]; long samples = 0; double sum = 0, peak = 0;
        while (samples < wanted)
        {
            int read = source.Read(buffer, 0, (int)Math.Min(buffer.Length, wanted - samples));
            if (read <= 0) throw new InvalidOperationException("empty-audio");
            for (int i = 0; i < read; i++) { sum += buffer[i] * buffer[i]; peak = Math.Max(peak, Math.Abs(buffer[i])); }
            samples += read;
        }
        return new { seconds = duration, samples, rms = Math.Sqrt(sum / samples), peak };
    }

    record Route(bool Connected, bool Verified, string Name, string Token, bool RequiresConfirmation);
    static Route CurrentRoute()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            using var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            if (device.State != DeviceState.Active) throw new InvalidOperationException("routeLost");
            var token = device.ID;
            if (token != observedToken) { confirmedToken = ""; observedToken = token; }
            var form = -1;
            try { form = Convert.ToInt32(device.Properties[PropertyKeys.PKEY_AudioEndpoint_FormFactor].Value); } catch { }
            var headphones = form == 3 || form == 5;
            return new Route(headphones || confirmedToken == token, headphones, device.FriendlyName, token, !headphones);
        }
        catch { confirmedToken = ""; observedToken = ""; return new Route(false, false, "", "", false); }
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
        var custom = sound.StartsWith("custom:");
        using var enumerator = new MMDeviceEnumerator(); selected = enumerator.GetDevice(route.Token); selectedToken = route.Token;
        reader = OpenSound(sound);
        var alarm = data.TryGetProperty("alarm", out var a) && a.GetBoolean();
        var preview = data.TryGetProperty("preview", out var p) && p.GetBoolean();
        loop = new LoopSource(reader, custom && alarm ? 60 : double.PositiveInfinity, preview ? Number(data, "startSeconds", 0, 7200) : 0);
        loop.Volume = alarm && !preview ? 0 : (float)Math.Clamp(data.GetProperty("volume").GetDouble(), 0, 1);
        output = new WasapiOut(selected, AudioClientShareMode.Shared, true, 100);
        var current = output;
        current.PlaybackStopped += (_, e) => { if (e.Exception != null) { Interlocked.Exchange(ref confirmedToken, ""); Emit(new { eventType = "routeLost" }); } };
        current.Init(loop.ToWaveProvider()); current.Play();
        previewEnd = preview ? DateTime.UtcNow.AddSeconds(Number(data, "previewSeconds", 4, 4)) : DateTime.MaxValue;
    }
    static void Check()
    {
        lock (Gate)
        {
            var route = CurrentRoute();
            if (output == null) return;
            if (DateTime.UtcNow >= previewEnd) { Stop(); return; }
            if (!route.Connected || route.Token != selectedToken || selected?.State != DeviceState.Active)
            {
                confirmedToken = ""; Stop(); Emit(new { eventType = "routeLost" });
            }
        }
    }
    static int Main(string[] args)
    {
        if (args.Length != 2) return 2;
        audioRoot = Path.GetFullPath(args[0]); mediaRoot = Path.GetFullPath(args[1]);
        using var timer = new Timer(_ => { try { Check(); } catch { lock (Gate) { confirmedToken = ""; Stop(); Emit(new { eventType = "routeLost" }); } } }, null, 100, 100);
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
                        case "confirmRoute":
                            var currentRoute = CurrentRoute();
                            var requestedToken = data.GetProperty("token").GetString();
                            if (string.IsNullOrEmpty(requestedToken) || requestedToken != currentRoute.Token) throw new InvalidOperationException("routeChanged");
                            confirmedToken = currentRoute.Token;
                            break;
                        case "inspect":
                            result = Inspect(data);
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
    private readonly long startPosition;
    public volatile float Volume;
    public WaveFormat WaveFormat => source.WaveFormat;
    public LoopSource(WaveStream stream, double limit, double start = 0)
    {
        this.stream = stream;
        if (!double.IsFinite(start) || start < 0 || start >= stream.TotalTime.TotalSeconds) throw new InvalidOperationException("invalid-start");
        stream.CurrentTime = TimeSpan.FromSeconds(start); startPosition = stream.Position;
        source = stream.ToSampleProvider();
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
                stream.Position = startPosition; source = stream.ToSampleProvider(); position = 0; continue;
            }
            resets = 0; total += read; position += read;
        }
        float volume = Volume; for (int i = 0; i < total; i++) buffer[offset + i] *= volume;
        return total;
    }
}
