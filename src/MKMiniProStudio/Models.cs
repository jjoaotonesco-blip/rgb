using System.Drawing;
using System.Text.Json;

namespace MKMiniProStudio;

internal sealed record KeyDefinition(string Label, int LedIndex, int X, int Y, int Width, int Height);

internal static class KeyboardLayout
{
    public const float NativeWidth = 671f;
    public const float NativeHeight = 235f;

    public static readonly KeyDefinition[] Keys =
    [
        new("Esc",0,15,11,41,41), new("1",7,58,11,41,41), new("2",13,101,11,41,41), new("3",19,144,11,41,41),
        new("4",25,187,11,41,41), new("5",31,230,11,41,41), new("6",37,273,11,41,41), new("7",43,316,11,41,41),
        new("8",49,359,11,41,41), new("9",55,402,11,41,41), new("0",61,445,11,41,41), new("-",67,488,11,41,41),
        new("=",73,531,11,41,41), new("Back",79,574,11,82,41),

        new("Tab",2,15,54,61,41), new("Q",8,78,54,41,41), new("W",14,121,54,41,41), new("E",20,164,54,41,41),
        new("R",26,207,54,41,41), new("T",32,250,54,41,41), new("Y",38,293,54,41,41), new("U",44,336,54,41,41),
        new("I",50,379,54,41,41), new("O",56,422,54,41,41), new("P",62,465,54,41,41), new("[",68,508,54,41,41),
        new("]",74,551,54,41,41), new("\\",80,594,54,62,41),

        new("Caps",3,15,97,67,41), new("A",9,84,97,41,41), new("S",15,127,97,41,41), new("D",21,170,97,41,41),
        new("F",27,213,97,41,41), new("G",33,256,97,41,41), new("H",39,299,97,41,41), new("J",45,342,97,41,41),
        new("K",51,385,97,41,41), new("L",57,428,97,41,41), new(";",63,471,97,41,41), new("'",69,514,97,41,41),
        new("Enter",81,557,97,99,41),

        new("Shift",4,15,140,101,41), new("Z",10,118,140,41,41), new("X",16,161,140,41,41), new("C",22,204,140,41,41),
        new("V",28,247,140,41,41), new("B",34,290,140,41,41), new("N",40,333,140,41,41), new("M",46,376,140,41,41),
        new(",",52,419,140,41,41), new(".",58,462,140,41,41), new("/",64,505,140,41,41), new("↑",94,548,140,41,41),
        new("Shift",76,591,140,65,41),

        new("Ctrl",5,15,183,55,41), new("Win",11,72,183,55,41), new("Alt",17,129,183,55,41), new("Space",35,186,183,255,41),
        new("Alt",65,443,183,41,41), new("←",89,486,183,41,41), new("↓",95,529,183,41,41), new("→",101,572,183,41,41),
        new("Fn",77,615,183,41,41)
    ];
}

internal sealed class RgbFrame
{
    public byte[] Data { get; private set; } = new byte[384];

    public Color GetColor(int ledIndex)
    {
        var o = ledIndex * 3;
        return Color.FromArgb(Data[o], Data[o + 1], Data[o + 2]);
    }

    public void SetColor(int ledIndex, Color color)
    {
        var o = ledIndex * 3;
        Data[o] = color.R;
        Data[o + 1] = color.G;
        Data[o + 2] = color.B;
    }

    public void Clear() => Array.Clear(Data);

    public void Fill(Color color)
    {
        Clear();
        foreach (var key in KeyboardLayout.Keys) SetColor(key.LedIndex, color);
    }

    public RgbFrame Clone()
    {
        var frame = new RgbFrame();
        Array.Copy(Data, frame.Data, Data.Length);
        return frame;
    }

    public static RgbFrame FromBytes(byte[] data)
    {
        if (data.Length != 384) throw new InvalidDataException("Frame RGB inválido.");
        var frame = new RgbFrame();
        Array.Copy(data, frame.Data, 384);
        return frame;
    }
}

internal sealed class StudioProject
{
    public int Fps { get; set; } = 12;
    public List<string> Frames { get; set; } = [];

    public static StudioProject FromFrames(IEnumerable<RgbFrame> frames, int fps) => new()
    {
        Fps = fps,
        Frames = frames.Select(f => Convert.ToBase64String(f.Data)).ToList()
    };

    public List<RgbFrame> DecodeFrames()
    {
        var result = new List<RgbFrame>();
        foreach (var encoded in Frames)
            result.Add(RgbFrame.FromBytes(Convert.FromBase64String(encoded)));
        return result;
    }

    public static StudioProject Load(string path)
    {
        var p = JsonSerializer.Deserialize<StudioProject>(File.ReadAllText(path), new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        return p ?? throw new InvalidDataException("Projeto vazio ou inválido.");
    }

    public void Save(string path) => File.WriteAllText(path, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
}
