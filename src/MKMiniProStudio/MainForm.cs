using System.Drawing;

namespace MKMiniProStudio;

internal sealed class MainForm : Form
{
    readonly MkMiniProDevice device = new();
    readonly KeyboardCanvas keyboard = new();
    readonly FlowLayoutPanel timeline = new();
    readonly Label hardwareStatus = new();
    readonly Label hint = new();
    readonly CheckBox livePreview = new();
    readonly ComboBox fpsBox = new();
    readonly CheckBox loopBox = new();
    readonly Button playButton = new();
    readonly Button colorButton = new();
    readonly NumericUpDown rBox = ChannelBox(), gBox = ChannelBox(), bBox = ChannelBox();
    readonly TextBox hexBox = new();
    readonly System.Windows.Forms.Timer playbackTimer = new();
    readonly System.Windows.Forms.Timer previewDebounce = new();
    readonly System.Windows.Forms.Timer hardwareTimer = new();

    readonly List<RgbFrame> frames = [new RgbFrame()];
    readonly List<Button> frameButtons = [];
    int selectedFrame;
    bool playing;
    bool syncingColor;
    bool previewSending;
    byte[]? pendingPreview;
    Color selectedColor = Color.FromArgb(0, 255, 120);

    static readonly Color Bg = Color.FromArgb(15, 17, 21);
    static readonly Color Panel = Color.FromArgb(23, 26, 32);
    static readonly Color Card = Color.FromArgb(31, 35, 43);
    static readonly Color Muted = Color.FromArgb(157, 166, 180);
    static readonly Color Accent = Color.FromArgb(108, 92, 231);

    RgbFrame Current => frames[selectedFrame];
    int Fps => fpsBox.SelectedItem is int n ? n : 12;

    public MainForm()
    {
        Text = "MKMINIPRO Studio";
        BackColor = Bg;
        ForeColor = Color.White;
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(980, 650);
        ClientSize = new Size(1240, 780);
        Font = new Font("Segoe UI", 10f);

        BuildUi();
        WireEvents();
        SetSelectedColor(selectedColor);
        SelectFrame(0, false);
        RefreshTimeline();
        RefreshHardwareStatus();

        playbackTimer.Interval = 1000 / Fps;
        previewDebounce.Interval = 45;
        hardwareTimer.Interval = 2000;
        hardwareTimer.Start();
    }

    void BuildUi()
    {
        var root = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1, Padding = new Padding(12) };
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 205));
        Controls.Add(root);

        var header = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, Padding = new Padding(3, 7, 3, 5) };
        var title = new Label { Text = "MKMINIPRO Studio", AutoSize = true, Font = new Font("Segoe UI Semibold", 17f), Margin = new Padding(2, 5, 22, 0) };
        hardwareStatus.AutoSize = true;
        hardwareStatus.Margin = new Padding(0, 11, 18, 0);
        livePreview.Text = "Preview no teclado";
        livePreview.AutoSize = true;
        livePreview.Checked = true;
        livePreview.Margin = new Padding(0, 10, 12, 0);
        var send = ActionButton("Fixar no teclado");
        send.Click += async (_, _) => await SendNowAsync();
        var save = ActionButton("Guardar projeto");
        save.Click += (_, _) => SaveProject();
        var open = ActionButton("Abrir projeto");
        open.Click += (_, _) => OpenProject();
        header.Controls.AddRange([title, hardwareStatus, livePreview, send, save, open]);
        root.Controls.Add(header, 0, 0);

        var middle = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, Margin = new Padding(0) };
        middle.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        middle.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 305));
        root.Controls.Add(middle, 0, 1);

        var keyboardPanel = new Panel { Dock = DockStyle.Fill, BackColor = Panel, Padding = new Padding(8), Margin = new Padding(0, 0, 8, 8) };
        keyboard.Dock = DockStyle.Fill;
        hint.Text = "Clique/arraste: pintar  •  botão direito: apagar";
        hint.ForeColor = Muted;
        hint.Dock = DockStyle.Bottom;
        hint.Height = 26;
        hint.TextAlign = ContentAlignment.MiddleCenter;
        keyboardPanel.Controls.Add(keyboard);
        keyboardPanel.Controls.Add(hint);
        middle.Controls.Add(keyboardPanel, 0, 0);

        var side = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true,
            BackColor = Panel, Padding = new Padding(12), Margin = new Padding(0, 0, 0, 8)
        };
        middle.Controls.Add(side, 1, 0);

        side.Controls.Add(SectionLabel("COR"));
        colorButton.Text = "Escolher cor";
        colorButton.Size = new Size(255, 42);
        colorButton.FlatStyle = FlatStyle.Flat;
        colorButton.FlatAppearance.BorderSize = 1;
        colorButton.ForeColor = Color.White;
        side.Controls.Add(colorButton);

        var rgbRow = new FlowLayoutPanel { Width = 260, Height = 52, FlowDirection = FlowDirection.LeftToRight, Margin = new Padding(0, 7, 0, 0) };
        rgbRow.Controls.AddRange([MiniLabel("R"), rBox, MiniLabel("G"), gBox, MiniLabel("B"), bBox]);
        side.Controls.Add(rgbRow);
        hexBox.Width = 255;
        hexBox.BackColor = Card;
        hexBox.ForeColor = Color.White;
        hexBox.BorderStyle = BorderStyle.FixedSingle;
        hexBox.PlaceholderText = "#00FF78";
        side.Controls.Add(hexBox);

        var quick = new FlowLayoutPanel { Width = 260, Height = 78, Margin = new Padding(0, 8, 0, 8) };
        AddQuickColor(quick, Color.Red, "R"); AddQuickColor(quick, Color.Lime, "G"); AddQuickColor(quick, Color.Blue, "B");
        AddQuickColor(quick, Color.White, "W"); AddQuickColor(quick, Color.Yellow, "Y"); AddQuickColor(quick, Color.Magenta, "P");
        side.Controls.Add(quick);

        side.Controls.Add(SectionLabel("PRESETS ESTÁTICOS"));
        var staticGrid = PresetGrid();
        AddPreset(staticGrid, "Apagar", () => ApplyFill(Color.Black));
        AddPreset(staticGrid, "Branco", () => ApplyFill(Color.White));
        AddPreset(staticGrid, "Vermelho", () => ApplyFill(Color.Red));
        AddPreset(staticGrid, "Verde", () => ApplyFill(Color.Lime));
        AddPreset(staticGrid, "Azul", () => ApplyFill(Color.Blue));
        AddPreset(staticGrid, "Portugal", ApplyPortugal);
        AddPreset(staticGrid, "Rainbow", ApplyRainbow);
        AddPreset(staticGrid, "Cor atual", () => ApplyFill(selectedColor));
        side.Controls.Add(staticGrid);

        side.Controls.Add(SectionLabel("ANIMAÇÕES"));
        var animGrid = PresetGrid();
        AddPreset(animGrid, "Rainbow Wave", () => GenerateAnimation(AnimationKind.Rainbow));
        AddPreset(animGrid, "Scanner", () => GenerateAnimation(AnimationKind.Scanner));
        AddPreset(animGrid, "Portugal Pulse", () => GenerateAnimation(AnimationKind.PortugalPulse));
        AddPreset(animGrid, "Color Wipe", () => GenerateAnimation(AnimationKind.Wipe));
        side.Controls.Add(animGrid);

        var bottom = new Panel { Dock = DockStyle.Fill, BackColor = Panel, Padding = new Padding(10), Margin = new Padding(0) };
        root.Controls.Add(bottom, 0, 2);
        var timelineHeader = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 48, WrapContents = false };
        playButton.Text = "▶ Play";
        playButton.Size = new Size(82, 34);
        StyleButton(playButton, Accent);
        timelineHeader.Controls.Add(playButton);
        timelineHeader.Controls.Add(ActionButton("+ Frame"));
        timelineHeader.Controls.Add(ActionButton("Duplicar"));
        timelineHeader.Controls.Add(ActionButton("Eliminar"));
        timelineHeader.Controls.Add(new Label { Text = "FPS", AutoSize = true, ForeColor = Muted, Margin = new Padding(18, 9, 5, 0) });
        fpsBox.DropDownStyle = ComboBoxStyle.DropDownList;
        fpsBox.Width = 70;
        foreach (var fps in new[] { 5, 10, 12, 15, 20, 24 }) fpsBox.Items.Add(fps);
        fpsBox.SelectedItem = 12;
        timelineHeader.Controls.Add(fpsBox);
        loopBox.Text = "Loop";
        loopBox.Checked = true;
        loopBox.AutoSize = true;
        loopBox.Margin = new Padding(14, 8, 0, 0);
        timelineHeader.Controls.Add(loopBox);

        // Wire timeline buttons by their text, avoiding extra field clutter.
        timelineHeader.Controls.OfType<Button>().First(b => b.Text == "+ Frame").Click += (_, _) => AddFrame();
        timelineHeader.Controls.OfType<Button>().First(b => b.Text == "Duplicar").Click += (_, _) => DuplicateFrame();
        timelineHeader.Controls.OfType<Button>().First(b => b.Text == "Eliminar").Click += (_, _) => DeleteFrame();

        timeline.Dock = DockStyle.Fill;
        timeline.FlowDirection = FlowDirection.LeftToRight;
        timeline.WrapContents = false;
        timeline.AutoScroll = true;
        timeline.Padding = new Padding(2, 8, 2, 2);
        timeline.BackColor = Color.FromArgb(18, 20, 25);
        bottom.Controls.Add(timeline);
        bottom.Controls.Add(timelineHeader);
    }

    void WireEvents()
    {
        keyboard.FrameChanged += (_, _) =>
        {
            UpdateSelectedTile();
            previewDebounce.Stop();
            previewDebounce.Start();
        };
        keyboard.KeyHovered += (_, key) => hint.Text = $"{key.Label}  •  LED {key.LedIndex}  •  clique/arraste pinta, botão direito apaga";
        colorButton.Click += (_, _) =>
        {
            using var dlg = new ColorDialog { Color = selectedColor, FullOpen = true };
            if (dlg.ShowDialog(this) == DialogResult.OK) SetSelectedColor(dlg.Color);
        };
        rBox.ValueChanged += (_, _) => ColorNumbersChanged();
        gBox.ValueChanged += (_, _) => ColorNumbersChanged();
        bBox.ValueChanged += (_, _) => ColorNumbersChanged();
        hexBox.KeyDown += (_, e) =>
        {
            if (e.KeyCode != Keys.Enter) return;
            try { SetSelectedColor(ColorTranslator.FromHtml(hexBox.Text.Trim())); }
            catch { System.Media.SystemSounds.Beep.Play(); }
            e.SuppressKeyPress = true;
        };
        playButton.Click += (_, _) => TogglePlayback();
        fpsBox.SelectedIndexChanged += (_, _) => playbackTimer.Interval = Math.Max(1, 1000 / Fps);
        playbackTimer.Tick += (_, _) => PlaybackTick();
        previewDebounce.Tick += (_, _) => { previewDebounce.Stop(); QueuePreview(Current); };
        hardwareTimer.Tick += (_, _) => RefreshHardwareStatus();
        FormClosed += (_, _) => device.Dispose();
    }

    void SetSelectedColor(Color color)
    {
        selectedColor = Color.FromArgb(color.R, color.G, color.B);
        keyboard.SelectedColor = selectedColor;
        colorButton.BackColor = selectedColor;
        colorButton.ForeColor = Luma(selectedColor) > 165 ? Color.Black : Color.White;
        syncingColor = true;
        rBox.Value = selectedColor.R; gBox.Value = selectedColor.G; bBox.Value = selectedColor.B;
        hexBox.Text = $"#{selectedColor.R:X2}{selectedColor.G:X2}{selectedColor.B:X2}";
        syncingColor = false;
    }

    void ColorNumbersChanged()
    {
        if (syncingColor) return;
        SetSelectedColor(Color.FromArgb((int)rBox.Value, (int)gBox.Value, (int)bBox.Value));
    }

    void AddQuickColor(Control parent, Color color, string text)
    {
        var b = new Button { Text = text, Width = 38, Height = 32, Margin = new Padding(2), BackColor = color, ForeColor = Luma(color) > 165 ? Color.Black : Color.White, FlatStyle = FlatStyle.Flat };
        b.FlatAppearance.BorderSize = 0;
        b.Click += (_, _) => SetSelectedColor(color);
        parent.Controls.Add(b);
    }

    void ApplyFill(Color color)
    {
        Current.Fill(color);
        keyboard.Invalidate();
        FrameEdited();
    }

    void ApplyPortugal()
    {
        Current.Clear();
        foreach (var key in KeyboardLayout.Keys)
            Current.SetColor(key.LedIndex, key.X < 250 ? Color.FromArgb(0, 132, 61) : Color.FromArgb(218, 41, 28));
        keyboard.Invalidate();
        FrameEdited();
    }

    void ApplyRainbow()
    {
        Current.Clear();
        foreach (var key in KeyboardLayout.Keys)
            Current.SetColor(key.LedIndex, Hsv((key.X / KeyboardLayout.NativeWidth) * 360.0, 1, 1));
        keyboard.Invalidate();
        FrameEdited();
    }

    enum AnimationKind { Rainbow, Scanner, PortugalPulse, Wipe }

    void GenerateAnimation(AnimationKind kind)
    {
        StopPlayback();
        frames.Clear();
        int count = kind == AnimationKind.PortugalPulse ? 20 : 24;
        for (int f = 0; f < count; f++)
        {
            var frame = new RgbFrame();
            foreach (var key in KeyboardLayout.Keys)
            {
                Color c = Color.Black;
                switch (kind)
                {
                    case AnimationKind.Rainbow:
                        c = Hsv(((key.X / KeyboardLayout.NativeWidth) * 360.0 + f * 15) % 360, 1, 1);
                        break;
                    case AnimationKind.Scanner:
                        var center = 15 + (KeyboardLayout.NativeWidth - 30) * f / (count - 1f);
                        var d = Math.Abs((key.X + key.Width / 2f) - center);
                        var v = Math.Clamp(1.0 - d / 115.0, 0, 1);
                        c = Color.FromArgb((int)(255 * v), 0, (int)(65 * v));
                        break;
                    case AnimationKind.PortugalPulse:
                        var br = 0.35 + 0.65 * (0.5 + 0.5 * Math.Sin(f * Math.PI * 2 / count));
                        var baseC = key.X < 250 ? Color.FromArgb(0, 132, 61) : Color.FromArgb(218, 41, 28);
                        c = Scale(baseC, br);
                        break;
                    case AnimationKind.Wipe:
                        var threshold = KeyboardLayout.NativeWidth * (f + 1) / count;
                        c = key.X <= threshold ? selectedColor : Color.Black;
                        break;
                }
                frame.SetColor(key.LedIndex, c);
            }
            frames.Add(frame);
        }
        selectedFrame = 0;
        keyboard.Frame = Current;
        RefreshTimeline();
        QueuePreview(Current);
    }

    void FrameEdited()
    {
        UpdateSelectedTile();
        previewDebounce.Stop();
        previewDebounce.Start();
    }

    void AddFrame()
    {
        StopPlayback();
        frames.Insert(selectedFrame + 1, new RgbFrame());
        SelectFrame(selectedFrame + 1, false);
        RefreshTimeline();
    }

    void DuplicateFrame()
    {
        StopPlayback();
        frames.Insert(selectedFrame + 1, Current.Clone());
        SelectFrame(selectedFrame + 1, false);
        RefreshTimeline();
    }

    void DeleteFrame()
    {
        StopPlayback();
        if (frames.Count == 1) { Current.Clear(); keyboard.Invalidate(); FrameEdited(); return; }
        frames.RemoveAt(selectedFrame);
        selectedFrame = Math.Min(selectedFrame, frames.Count - 1);
        keyboard.Frame = Current;
        RefreshTimeline();
        QueuePreview(Current);
    }

    void SelectFrame(int index, bool preview = true)
    {
        if (index < 0 || index >= frames.Count) return;
        selectedFrame = index;
        keyboard.Frame = Current;
        for (int i = 0; i < frameButtons.Count; i++)
        {
            frameButtons[i].FlatAppearance.BorderSize = i == selectedFrame ? 3 : 1;
            frameButtons[i].FlatAppearance.BorderColor = i == selectedFrame ? Accent : Color.FromArgb(75, 82, 96);
        }
        if (preview) QueuePreview(Current);
    }

    void RefreshTimeline()
    {
        timeline.SuspendLayout();
        timeline.Controls.Clear();
        frameButtons.Clear();
        for (int i = 0; i < frames.Count; i++)
        {
            var index = i;
            var avg = AverageColor(frames[i]);
            var b = new Button
            {
                Text = (i + 1).ToString(), Tag = i, Width = 58, Height = 74, Margin = new Padding(4),
                BackColor = avg, ForeColor = Luma(avg) > 165 ? Color.Black : Color.White,
                FlatStyle = FlatStyle.Flat, Font = new Font("Segoe UI Semibold", 10f)
            };
            b.FlatAppearance.BorderSize = i == selectedFrame ? 3 : 1;
            b.FlatAppearance.BorderColor = i == selectedFrame ? Accent : Color.FromArgb(75, 82, 96);
            b.Click += (_, _) => SelectFrame(index);
            frameButtons.Add(b);
            timeline.Controls.Add(b);
        }
        timeline.ResumeLayout();
    }

    void UpdateSelectedTile()
    {
        if (selectedFrame < 0 || selectedFrame >= frameButtons.Count) return;
        var b = frameButtons[selectedFrame];
        var avg = AverageColor(Current);
        b.BackColor = avg;
        b.ForeColor = Luma(avg) > 165 ? Color.Black : Color.White;
    }

    void TogglePlayback()
    {
        if (playing) StopPlayback();
        else
        {
            playing = true;
            playButton.Text = "■ Stop";
            playbackTimer.Interval = Math.Max(1, 1000 / Fps);
            playbackTimer.Start();
            QueuePreview(Current);
        }
    }

    void StopPlayback()
    {
        playing = false;
        playbackTimer.Stop();
        playButton.Text = "▶ Play";
    }

    void PlaybackTick()
    {
        var next = selectedFrame + 1;
        if (next >= frames.Count)
        {
            if (!loopBox.Checked) { StopPlayback(); return; }
            next = 0;
        }
        SelectFrame(next);
    }

    async Task SendNowAsync()
    {
        try
        {
            SetHardwareStatus("A fixar no teclado…", Color.Gold);
            // Stop queued live preview first; the persistent write itself is one-shot.
            previewDebounce.Stop();
            pendingPreview = null;
            await device.SendPersistentFrameAsync((byte[])Current.Data.Clone());
            SetHardwareStatus("● Ligado • cor fixa gravada", Color.FromArgb(73, 220, 129));
        }
        catch (Exception ex)
        {
            SetHardwareStatus("● Erro RGB", Color.FromArgb(255, 105, 105));
            MessageBox.Show(this, ex.Message, "MKMINIPRO Studio", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    void QueuePreview(RgbFrame frame)
    {
        if (!livePreview.Checked) return;
        pendingPreview = (byte[])frame.Data.Clone();
        if (!previewSending) _ = DrainPreviewAsync();
    }

    async Task DrainPreviewAsync()
    {
        if (previewSending) return;
        previewSending = true;
        try
        {
            while (pendingPreview is not null)
            {
                var next = pendingPreview;
                pendingPreview = null;
                try
                {
                    await device.SendFrameAsync(next);
                    if (!IsDisposed) SetHardwareStatus("● Ligado", Color.FromArgb(73, 220, 129));
                }
                catch (Exception ex)
                {
                    if (!IsDisposed) SetHardwareStatus("● " + ShortError(ex.Message), Color.FromArgb(255, 105, 105));
                    pendingPreview = null;
                    break;
                }
            }
        }
        finally
        {
            previewSending = false;
            if (pendingPreview is not null && !IsDisposed) _ = DrainPreviewAsync();
        }
    }

    void RefreshHardwareStatus()
    {
        var present = MkMiniProDevice.IsPresent();
        SetHardwareStatus(present ? "● MKMINIPRO ligado" : "● MKMINIPRO não encontrado", present ? Color.FromArgb(73, 220, 129) : Color.FromArgb(255, 105, 105));
    }

    void SetHardwareStatus(string text, Color color)
    {
        if (InvokeRequired) { BeginInvoke(new Action(() => SetHardwareStatus(text, color))); return; }
        hardwareStatus.Text = text;
        hardwareStatus.ForeColor = color;
    }

    void SaveProject()
    {
        using var dlg = new SaveFileDialog { Filter = "MKMINIPRO Studio (*.mkrgb)|*.mkrgb|JSON (*.json)|*.json", DefaultExt = "mkrgb", FileName = "animation.mkrgb" };
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        StudioProject.FromFrames(frames, Fps).Save(dlg.FileName);
    }

    void OpenProject()
    {
        using var dlg = new OpenFileDialog { Filter = "MKMINIPRO Studio (*.mkrgb;*.json)|*.mkrgb;*.json|Todos os ficheiros (*.*)|*.*" };
        if (dlg.ShowDialog(this) != DialogResult.OK) return;
        try
        {
            var project = StudioProject.Load(dlg.FileName);
            var loaded = project.DecodeFrames();
            if (loaded.Count == 0) throw new InvalidDataException("O projeto não contém frames.");
            StopPlayback();
            frames.Clear(); frames.AddRange(loaded);
            selectedFrame = 0;
            if (fpsBox.Items.Contains(project.Fps)) fpsBox.SelectedItem = project.Fps;
            keyboard.Frame = Current;
            RefreshTimeline();
            QueuePreview(Current);
        }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Projeto inválido", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }

    static Color AverageColor(RgbFrame frame)
    {
        long r = 0, g = 0, b = 0;
        foreach (var key in KeyboardLayout.Keys)
        {
            var c = frame.GetColor(key.LedIndex); r += c.R; g += c.G; b += c.B;
        }
        var n = KeyboardLayout.Keys.Length;
        return Color.FromArgb((int)(r / n), (int)(g / n), (int)(b / n));
    }

    static Color Hsv(double h, double s, double v)
    {
        h = (h % 360 + 360) % 360;
        var c = v * s; var x = c * (1 - Math.Abs((h / 60) % 2 - 1)); var m = v - c;
        (double r, double g, double b) = h switch
        {
            < 60 => (c, x, 0d), < 120 => (x, c, 0d), < 180 => (0d, c, x),
            < 240 => (0d, x, c), < 300 => (x, 0d, c), _ => (c, 0d, x)
        };
        return Color.FromArgb((int)((r + m) * 255), (int)((g + m) * 255), (int)((b + m) * 255));
    }

    static Color Scale(Color c, double amount) => Color.FromArgb((int)(c.R * amount), (int)(c.G * amount), (int)(c.B * amount));
    static int Luma(Color c) => (int)(0.299 * c.R + 0.587 * c.G + 0.114 * c.B);
    static string ShortError(string text) => text.Length <= 36 ? text : text[..33] + "…";

    static NumericUpDown ChannelBox() => new() { Minimum = 0, Maximum = 255, Width = 48, Height = 30, BackColor = Card, ForeColor = Color.White, BorderStyle = BorderStyle.FixedSingle };
    static Label MiniLabel(string text) => new() { Text = text, AutoSize = true, ForeColor = Muted, Margin = new Padding(2, 7, 2, 0) };
    static Label SectionLabel(string text) => new() { Text = text, AutoSize = true, ForeColor = Muted, Font = new Font("Segoe UI Semibold", 9f), Margin = new Padding(0, 10, 0, 5) };

    static Button ActionButton(string text)
    {
        var b = new Button { Text = text, AutoSize = true, Height = 34, Padding = new Padding(7, 0, 7, 0), Margin = new Padding(3, 2, 3, 0) };
        StyleButton(b, Card); return b;
    }

    static void StyleButton(Button b, Color back)
    {
        b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = Color.FromArgb(73, 79, 92); b.FlatAppearance.BorderSize = 1;
        b.BackColor = back; b.ForeColor = Color.White; b.Cursor = Cursors.Hand;
    }

    static TableLayoutPanel PresetGrid()
    {
        var grid = new TableLayoutPanel { Width = 260, AutoSize = true, ColumnCount = 2, Margin = new Padding(0, 0, 0, 8) };
        grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50)); grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50));
        return grid;
    }

    static void AddPreset(TableLayoutPanel grid, string text, Action action)
    {
        var b = new Button { Text = text, Dock = DockStyle.Fill, Height = 36, Margin = new Padding(2), FlatStyle = FlatStyle.Flat, BackColor = Card, ForeColor = Color.White };
        b.FlatAppearance.BorderColor = Color.FromArgb(65, 71, 84);
        b.Click += (_, _) => action();
        var pos = grid.Controls.Count;
        grid.Controls.Add(b, pos % 2, pos / 2);
    }
}

