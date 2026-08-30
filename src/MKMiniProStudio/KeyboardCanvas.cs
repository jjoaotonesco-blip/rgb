using System.Drawing.Drawing2D;

namespace MKMiniProStudio;

internal sealed class KeyboardCanvas : Control
{
    RgbFrame frame = new();
    bool painting;
    MouseButtons paintButton;
    int lastLed = -1;

    public event EventHandler? FrameChanged;
    public event EventHandler<KeyDefinition>? KeyHovered;

    public RgbFrame Frame
    {
        get => frame;
        set { frame = value; Invalidate(); }
    }

    public Color SelectedColor { get; set; } = Color.FromArgb(0, 255, 120);

    public KeyboardCanvas()
    {
        DoubleBuffered = true;
        ResizeRedraw = true;
        BackColor = Color.FromArgb(19, 21, 26);
        ForeColor = Color.White;
        MinimumSize = new Size(500, 210);
        Cursor = Cursors.Hand;
        SetStyle(ControlStyles.Selectable, true);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        var scale = Math.Min((ClientSize.Width - 24f) / KeyboardLayout.NativeWidth, (ClientSize.Height - 24f) / KeyboardLayout.NativeHeight);
        if (scale <= 0) return;
        var ox = (ClientSize.Width - KeyboardLayout.NativeWidth * scale) / 2f;
        var oy = (ClientSize.Height - KeyboardLayout.NativeHeight * scale) / 2f;

        using var border = new Pen(Color.FromArgb(76, 82, 94), Math.Max(1f, scale));
        using var labelBrush = new SolidBrush(Color.White);
        using var dimBrush = new SolidBrush(Color.FromArgb(34, 37, 44));

        foreach (var key in KeyboardLayout.Keys)
        {
            var rect = ToScreen(key, scale, ox, oy);
            var c = Frame.GetColor(key.LedIndex);
            var brightness = Math.Max(c.R, Math.Max(c.G, c.B));
            using var fill = new SolidBrush(brightness < 8 ? dimBrush.Color : c);
            using var path = RoundedRect(rect, Math.Max(4f, 5f * scale));
            e.Graphics.FillPath(fill, path);
            e.Graphics.DrawPath(border, path);

            var textColor = brightness > 150 && (c.R + c.G + c.B) > 420 ? Color.Black : Color.White;
            using var tb = new SolidBrush(textColor);
            var fontSize = Math.Clamp(9f * scale, 7f, 13f);
            using var font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
            var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            e.Graphics.DrawString(key.Label, font, tb, rect, sf);
        }
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        Focus();
        if (e.Button is not (MouseButtons.Left or MouseButtons.Right)) return;
        painting = true;
        paintButton = e.Button;
        lastLed = -1;
        PaintAt(e.Location);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var key = HitTest(e.Location);
        if (key is not null) KeyHovered?.Invoke(this, key);
        if (painting) PaintAt(e.Location);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        painting = false;
        lastLed = -1;
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        if ((Control.MouseButtons & (MouseButtons.Left | MouseButtons.Right)) == 0) painting = false;
    }

    void PaintAt(Point p)
    {
        var key = HitTest(p);
        if (key is null || key.LedIndex == lastLed) return;
        lastLed = key.LedIndex;
        Frame.SetColor(key.LedIndex, paintButton == MouseButtons.Right ? Color.Black : SelectedColor);
        Invalidate();
        FrameChanged?.Invoke(this, EventArgs.Empty);
    }

    KeyDefinition? HitTest(Point p)
    {
        var scale = Math.Min((ClientSize.Width - 24f) / KeyboardLayout.NativeWidth, (ClientSize.Height - 24f) / KeyboardLayout.NativeHeight);
        if (scale <= 0) return null;
        var ox = (ClientSize.Width - KeyboardLayout.NativeWidth * scale) / 2f;
        var oy = (ClientSize.Height - KeyboardLayout.NativeHeight * scale) / 2f;
        foreach (var key in KeyboardLayout.Keys)
            if (ToScreen(key, scale, ox, oy).Contains(p)) return key;
        return null;
    }

    static RectangleF ToScreen(KeyDefinition key, float scale, float ox, float oy) =>
        new(ox + key.X * scale, oy + key.Y * scale, key.Width * scale, key.Height * scale);

    static GraphicsPath RoundedRect(RectangleF r, float radius)
    {
        var d = radius * 2f;
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}
