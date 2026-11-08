// Summarises an EventPipe CPU-sampling trace of the game (SDV_TRACE=1):
// where the game's main thread was while frames were slow.
//
//   TraceReport <trace.nettrace> [slow-frame.csv] [min_ms]
//
// The sample profiler records every managed thread's stack about once a
// millisecond, including threads that are blocked, so a frame that stalls
// in a wait, a native call or a lock shows up with the call that stalled.
using System.Globalization;
using Microsoft.Diagnostics.Tracing.Etlx;

if (args.Length < 1)
{
    Console.Error.WriteLine("usage: TraceReport <trace.nettrace> [slow-frame.csv] [min_ms]");
    return 2;
}

var tracePath = args[0];
var csvPath = args.Length > 1 ? args[1] : null;
var minMs = args.Length > 2 ? double.Parse(args[2], CultureInfo.InvariantCulture) : 80;
const int LeafFrames = 16;

if (!File.Exists(tracePath) || new FileInfo(tracePath).Length == 0)
{
    Console.WriteLine($"No trace data in {tracePath}. This .NET build may not support EventPipe.");
    return 1;
}

TraceLog log;
// TraceEvent converts the trace into a (large) .etlx file first; removed on exit.
var etlx = tracePath + ".etlx";
AppDomain.CurrentDomain.ProcessExit += (_, _) => { try { File.Delete(etlx); } catch { } };
try
{
    TraceLog.CreateFromEventPipeDataFile(tracePath, etlx, new TraceLogOptions { ContinueOnError = true });
    log = new TraceLog(etlx);
}
catch (Exception ex)
{
    Console.WriteLine($"Could not read {tracePath}: {ex.Message}");
    return 1;
}

using (log)
{
    // Slow frames from the MonoGame frame profiler. The utc column is when
    // the frame finished; tick_ms is how long it took.
    var windows = new List<(DateTime start, DateTime end, double ms)>();
    if (csvPath != null && File.Exists(csvPath))
    {
        foreach (var line in File.ReadLines(csvPath).Skip(1))
        {
            var f = line.Split(',');
            if (f.Length < 4) continue;
            if (!DateTime.TryParse(f[0], CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal, out var end)) continue;
            if (!double.TryParse(f[3], NumberStyles.Float, CultureInfo.InvariantCulture, out var ms)) continue;
            if (ms >= minMs) windows.Add((end.AddMilliseconds(-ms), end, ms));
        }
    }

    var samples = new List<(int tid, DateTime utc, TraceCallStack? stack)>();
    foreach (var ev in log.Events)
    {
        if (ev.ProviderName == "Microsoft-DotNETCore-SampleProfiler")
            samples.Add((ev.ThreadID, ev.TimeStamp.ToUniversalTime(), ev.CallStack()));
    }

    Console.WriteLine($"Trace: {tracePath}");
    Console.WriteLine($"Samples: {samples.Count} from {samples.Select(s => s.tid).Distinct().Count()} threads");
    if (samples.Count == 0)
    {
        Console.WriteLine("No CPU samples were recorded.");
        return 1;
    }
    Console.WriteLine($"Span (UTC): {samples.Min(s => s.utc):HH:mm:ss.fff} - {samples.Max(s => s.utc):HH:mm:ss.fff}");

    // The game's main thread runs MonoGame's Game.Tick.
    var mainTid = samples
        .Where(s => s.stack != null && Frames(s.stack, 300).Any(f => f.StartsWith("Microsoft.Xna.Framework.Game.Tick", StringComparison.Ordinal)))
        .GroupBy(s => s.tid).OrderByDescending(g => g.Count()).Select(g => (int?)g.Key).FirstOrDefault();
    if (mainTid == null)
    {
        Console.WriteLine("Could not find the game's main thread (no Game.Tick frames).");
        return 1;
    }
    Console.WriteLine($"Main thread: {mainTid}");

    var main = samples.Where(s => s.tid == mainTid && s.stack != null).ToList();

    if (windows.Count > 0)
    {
        // A little slack on both sides: the two clocks are sampled separately.
        var slack = TimeSpan.FromMilliseconds(5);
        var inSlow = main.Where(s => windows.Any(w => s.utc >= w.start - slack && s.utc <= w.end + slack)).ToList();
        Console.WriteLine($"Slow frames >= {minMs} ms: {windows.Count} (longest {windows.Max(w => w.ms):F0} ms, total {windows.Sum(w => w.ms):F0} ms)");
        Report($"MAIN THREAD DURING SLOW FRAMES (>= {minMs} ms)", inSlow);
    }
    else
    {
        Console.WriteLine("No slow-frame log given or no frames over the threshold; reporting the whole trace.");
    }

    Report("MAIN THREAD, WHOLE TRACE", main);
    return 0;
}

static void Report(string title, List<(int tid, DateTime utc, TraceCallStack? stack)> list)
{
    Console.WriteLine();
    Console.WriteLine($"===== {title}: {list.Count} samples =====");
    if (list.Count == 0) return;

    Console.WriteLine();
    Console.WriteLine("-- Inclusive: share of samples with this method on the stack (top 50) --");
    var inclusive = new Dictionary<string, int>();
    foreach (var s in list)
        foreach (var f in Frames(s.stack!, 300).Distinct())
            inclusive[f] = inclusive.GetValueOrDefault(f) + 1;
    foreach (var kv in inclusive.OrderByDescending(k => k.Value).Take(50))
        Console.WriteLine($"{kv.Value * 100.0 / list.Count,6:F1}%  {kv.Key}");

    Console.WriteLine();
    Console.WriteLine($"-- Most common stacks (innermost {LeafFrames} frames, top 15) --");
    foreach (var g in list.GroupBy(s => string.Join("\n        <- ", Frames(s.stack!, LeafFrames)))
                          .OrderByDescending(g => g.Count()).Take(15))
    {
        Console.WriteLine();
        Console.WriteLine($"[{g.Count() * 100.0 / list.Count:F1}%] {g.Key}");
    }
}

static IEnumerable<string> Frames(TraceCallStack stack, int max)
{
    for (var s = stack; s != null && max-- > 0; s = s.Caller)
    {
        var name = s.CodeAddress.FullMethodName;
        yield return string.IsNullOrEmpty(name) ? (s.CodeAddress.ModuleName is { Length: > 0 } m ? m + "!?" : "?") : name;
    }
}
