using System;
using System.IO;
using System.Threading;

[AttributeUsage(AttributeTargets.Class)]
public class ModEntryPointAttribute : Attribute
{
}

[ModEntryPoint]
public static class StardewPatches
{
    // Loaded by the patched MonoGame (MONOGAME_PATCH) before the game starts.
    public static void Main()
    {
        Console.Out.WriteLine("StardewPatches initialized");
        ExceptionLog.Start(Environment.GetEnvironmentVariable("SDV_EXCEPTION_LOG"));
    }
}

// Opt-in first-chance exception log (SDV_EXCEPTION_LOG=<file>).
// The game catches and re-wraps some errors (e.g. "Could not load <asset>
// asset!"), hiding the underlying I/O or decoding failure. Logging every
// exception as it is thrown keeps the original cause.
internal static class ExceptionLog
{
    private const int MaxEntries = 500;

    private static readonly object Sync = new object();
    private static StreamWriter _writer;
    private static int _count;

    [ThreadStatic]
    private static bool _inHandler;

    public static void Start(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            return;

        try
        {
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir))
                Directory.CreateDirectory(dir);
            _writer = new StreamWriter(path, append: false) { AutoFlush = true };
            _writer.WriteLine($"# first-chance exceptions, started {DateTime.Now:O}");
            AppDomain.CurrentDomain.FirstChanceException += OnFirstChance;
            AppDomain.CurrentDomain.UnhandledException += (_, e) =>
                Write("UNHANDLED", e.ExceptionObject as Exception);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("StardewPatches: exception log disabled: " + ex.Message);
        }
    }

    private static void OnFirstChance(object sender, System.Runtime.ExceptionServices.FirstChanceExceptionEventArgs e)
    {
        Write("first-chance", e.Exception);
    }

    private static void Write(string kind, Exception ex)
    {
        if (_inHandler || ex == null || _writer == null)
            return;

        _inHandler = true;
        try
        {
            lock (Sync)
            {
                if (_count >= MaxEntries)
                    return;
                _count++;
                _writer.WriteLine($"--- [{DateTime.Now:HH:mm:ss.fff}] {kind} on thread {Thread.CurrentThread.ManagedThreadId} ({Thread.CurrentThread.Name})");
                _writer.WriteLine(ex.ToString());
                if (_count == MaxEntries)
                    _writer.WriteLine($"# limit of {MaxEntries} entries reached");
            }
        }
        catch
        {
            // never let logging break the game
        }
        finally
        {
            _inHandler = false;
        }
    }
}
