using Namespace System.Drawing
using Namespace System.Drawing.Drawing2D
using Namespace System.Windows.Forms

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$Width = 700
$Height = 700
$CenterX = [float]($Width / 2)
$CenterY = [float]($Height / 2)
$ClockRadius = 255.0

$Form = [Form]@{
    Text            = 'www.inilog.com'
    ClientSize      = [Size]::new($Width, $Height)
    BackColor       = [Color]::FromArgb(8, 10, 16)
    FormBorderStyle = [FormBorderStyle]::FixedSingle
    MaximizeBox     = $false
    StartPosition   = 'CenterScreen'
}

$DoubleBufferedProp = [Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
$DoubleBufferedProp.SetValue($Form, $true, $null)

function Get-PolarPoint {
    param(
        [float]$cx,
        [float]$cy,
        [double]$radius,
        [double]$angleDeg
    )
    $rad = ($angleDeg - 90.0) * [Math]::PI / 180.0
    $x = $cx + ($radius * [Math]::Cos($rad))
    $y = $cy + ($radius * [Math]::Sin($rad))
    return [PointF]::new([float]$x, [float]$y)
}

function Draw-ModernHand {
    param(
        [Graphics]$g,
        [float]$cx,
        [float]$cy,
        [double]$angleDeg,
        [double]$length,
        [double]$tailLength,
        [float]$width,
        [Color]$color,
        [bool]$withGlow = $false
    )
    $tip = Get-PolarPoint -cx $cx -cy $cy -radius $length -angleDeg $angleDeg
    $tail = Get-PolarPoint -cx $cx -cy $cy -radius (-$tailLength) -angleDeg $angleDeg

    if ($withGlow) {
        $glowPen = [Pen]::new([Color]::FromArgb(45, $color.R, $color.G, $color.B), ($width + 6.0))
        $glowPen.StartCap = [LineCap]::Round
        $glowPen.EndCap = [LineCap]::Round
        $g.DrawLine($glowPen, $tail, $tip)
        $glowPen.Dispose()
    }

    $pen = [Pen]::new($color, $width)
    $pen.StartCap = [LineCap]::Round
    $pen.EndCap = [LineCap]::Round
    $g.DrawLine($pen, $tail, $tip)
    $pen.Dispose()
}

$Form.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $now = [DateTime]::Now
    $g.Clear([Color]::FromArgb(8, 10, 16))

    # --- MOSTRADOR MODERNO COM GRADIENTE RADIAL ---
    $dialRect = [RectangleF]::new(($CenterX - $ClockRadius), ($CenterY - $ClockRadius), ($ClockRadius * 2), ($ClockRadius * 2))
    $dialPath = [GraphicsPath]::new()
    $dialPath.AddEllipse($dialRect)

    $dialGrad = [PathGradientBrush]::new($dialPath)
    $dialGrad.CenterPoint = [PointF]::new($CenterX, ($CenterY - 25.0))
    $dialGrad.CenterColor = [Color]::FromArgb(255, 24, 32, 48)
    $dialGrad.SurroundColors = @([Color]::FromArgb(255, 10, 13, 21))
    $g.FillPath($dialGrad, $dialPath)
    $dialGrad.Dispose()
    $dialPath.Dispose()

    # Anel externo moderno com brilho sutil
    $outerGlowPen = [Pen]::new([Color]::FromArgb(42, 56, 189, 248), 10.0)
    $g.DrawEllipse($outerGlowPen, $dialRect)
    $outerGlowPen.Dispose()

    $outerRingPen = [Pen]::new([Color]::FromArgb(235, 56, 189, 248), 2.5)
    $g.DrawEllipse($outerRingPen, $dialRect)
    $outerRingPen.Dispose()

    # Anéis internos minimalistas
    $rTrackOuter = $ClockRadius - 12.0
    $rTrackInner = $ClockRadius - 26.0
    $trackPen = [Pen]::new([Color]::FromArgb(45, 148, 163, 184), 1.0)
    $g.DrawEllipse($trackPen, ($CenterX - $rTrackOuter), ($CenterY - $rTrackOuter), ($rTrackOuter * 2), ($rTrackOuter * 2))
    $g.DrawEllipse($trackPen, ($CenterX - $rTrackInner), ($CenterY - $rTrackInner), ($rTrackInner * 2), ($rTrackInner * 2))
    $trackPen.Dispose()

    # Arco de progresso dos segundos ao redor da borda interna
    $secExact = $now.Second + ($now.Millisecond / 1000.0)
    $secSweep = [float](($secExact / 60.0) * 360.0)
    $rArc = $ClockRadius - 19.0
    $arcRect = [RectangleF]::new(($CenterX - $rArc), ($CenterY - $rArc), ($rArc * 2), ($rArc * 2))
    $secArcPen = [Pen]::new([Color]::FromArgb(145, 56, 189, 248), 2.2)
    $secArcPen.StartCap = [LineCap]::Round
    $secArcPen.EndCap = [LineCap]::Round
    $g.DrawArc($secArcPen, $arcRect, -90.0, $secSweep)
    $secArcPen.Dispose()

    # Escala de 60 minutos e marcadores de hora
    for ($i = 0; $i -lt 60; $i++) {
        $deg = $i * 6.0
        $isHour = ($i % 5 -eq 0)
        $isMajor = ($i % 15 -eq 0)

        $rOuter = $ClockRadius - 28.0
        $rInner = if ($isMajor) { $ClockRadius - 46.0 } elseif ($isHour) { $ClockRadius - 42.0 } else { $ClockRadius - 34.0 }
        $width = if ($isMajor) { 3.6 } elseif ($isHour) { 2.6 } else { 1.1 }

        $col = if ($isMajor) {
            [Color]::FromArgb(250, 248, 250, 252)
        }
        elseif ($isHour) {
            [Color]::FromArgb(200, 148, 210, 255)
        }
        else {
            [Color]::FromArgb(85, 148, 163, 184)
        }

        $p1 = Get-PolarPoint -cx $CenterX -cy $CenterY -radius $rInner -angleDeg $deg
        $p2 = Get-PolarPoint -cx $CenterX -cy $CenterY -radius $rOuter -angleDeg $deg

        $tickPen = [Pen]::new($col, $width)
        $tickPen.StartCap = [LineCap]::Round
        $tickPen.EndCap = [LineCap]::Round
        $g.DrawLine($tickPen, $p1, $p2)
        $tickPen.Dispose()
    }

    # Números modernos (12, 3, 6, 9 em destaque e demais discretos)
    $cardinalFont = [Font]::new('Segoe UI', 16.0, [FontStyle]::Bold)
    $hourFont = [Font]::new('Segoe UI', 12.0, [FontStyle]::Regular)
    $sf = [StringFormat]::new()
    $sf.Alignment = [StringAlignment]::Center
    $sf.LineAlignment = [StringAlignment]::Center

    for ($h = 1; $h -le 12; $h++) {
        $deg = ($h % 12) * 30.0
        $isCardinal = ($h -in @(12, 3, 6, 9))
        $numPt = Get-PolarPoint -cx $CenterX -cy $CenterY -radius ($ClockRadius - 68.0) -angleDeg $deg
        $numRect = [RectangleF]::new(($numPt.X - 20), ($numPt.Y - 15), 40, 30)

        if ($isCardinal) {
            $b = [SolidBrush]::new([Color]::FromArgb(250, 241, 245, 249))
            $g.DrawString("$h", $cardinalFont, $b, $numRect, $sf)
            $b.Dispose()
        }
        else {
            $b = [SolidBrush]::new([Color]::FromArgb(165, 148, 163, 184))
            $g.DrawString("$h", $hourFont, $b, $numRect, $sf)
            $b.Dispose()
        }
    }

    $sf.Dispose()
    $cardinalFont.Dispose()
    $hourFont.Dispose()

    # Visor minimalista de data e hora digital
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('pt-BR')
    $dateStr = $now.ToString("ddd, dd MMM", $culture).ToUpper()
    $timeStr = $now.ToString("HH:mm:ss")

    $badgeW = 124.0
    $badgeH = 46.0
    $badgeX = $CenterX - ($badgeW / 2.0)
    $badgeY = $CenterY + 56.0
    $badgeRect = [RectangleF]::new($badgeX, $badgeY, $badgeW, $badgeH)

    $badgeBrush = [SolidBrush]::new([Color]::FromArgb(220, 13, 18, 29))
    $badgePen = [Pen]::new([Color]::FromArgb(95, 56, 189, 248), 1.0)
    $g.FillRectangle($badgeBrush, $badgeRect)
    $g.DrawRectangle($badgePen, $badgeRect.X, $badgeRect.Y, $badgeRect.Width, $badgeRect.Height)
    $badgePen.Dispose()
    $badgeBrush.Dispose()

    $dateFont = [Font]::new('Segoe UI', 8.5, [FontStyle]::Bold)
    $timeFont = [Font]::new('Consolas', 11.0, [FontStyle]::Bold)
    $dateBrush = [SolidBrush]::new([Color]::FromArgb(215, 148, 163, 184))
    $timeBrush = [SolidBrush]::new([Color]::FromArgb(250, 56, 189, 248))

    $dateSf = [StringFormat]::new()
    $dateSf.Alignment = [StringAlignment]::Center
    $g.DrawString($dateStr, $dateFont, $dateBrush, [RectangleF]::new($badgeX, ($badgeY + 5.0), $badgeW, 16.0), $dateSf)
    $g.DrawString($timeStr, $timeFont, $timeBrush, [RectangleF]::new($badgeX, ($badgeY + 21.0), $badgeW, 20.0), $dateSf)
    $dateSf.Dispose()

    $dateBrush.Dispose()
    $timeBrush.Dispose()
    $dateFont.Dispose()
    $timeFont.Dispose()

    # Cálculo preciso dos ponteiros
    $minExact = $now.Minute + ($secExact / 60.0)
    $hourExact = ($now.Hour % 12) + ($minExact / 60.0)

    $secAngle = $secExact * 6.0
    $minAngle = $minExact * 6.0
    $hourAngle = $hourExact * 30.0

    # Hora (branco gelo), Minuto (azul claro moderno), Segundo (ciano vibrante com brilho)
    Draw-ModernHand -g $g -cx $CenterX -cy $CenterY -angleDeg $hourAngle -length ($ClockRadius * 0.50) -tailLength 16.0 -width 7.0 -color ([Color]::FromArgb(250, 241, 245, 249)) -withGlow $false
    Draw-ModernHand -g $g -cx $CenterX -cy $CenterY -angleDeg $minAngle  -length ($ClockRadius * 0.74) -tailLength 22.0 -width 4.5 -color ([Color]::FromArgb(250, 125, 211, 252)) -withGlow $false
    Draw-ModernHand -g $g -cx $CenterX -cy $CenterY -angleDeg $secAngle  -length ($ClockRadius * 0.85) -tailLength 28.0 -width 2.0 -color ([Color]::FromArgb(255, 56, 189, 248))  -withGlow $true

    # Pino central em camadas
    $capOuter = [SolidBrush]::new([Color]::FromArgb(255, 56, 189, 248))
    $capMid = [SolidBrush]::new([Color]::FromArgb(255, 241, 245, 249))
    $capInner = [SolidBrush]::new([Color]::FromArgb(15, 23, 42))
    $g.FillEllipse($capOuter, ($CenterX - 9.0), ($CenterY - 9.0), 18.0, 18.0)
    $g.FillEllipse($capMid, ($CenterX - 5.5), ($CenterY - 5.5), 11.0, 11.0)
    $g.FillEllipse($capInner, ($CenterX - 2.5), ($CenterY - 2.5), 5.0, 5.0)
    $capInner.Dispose()
    $capMid.Dispose()
    $capOuter.Dispose()
})

$Timer = [Timer]@{ Interval = 30 }
$Timer.Add_Tick({
    $Form.Invalidate()
})

$Form.Add_FormClosing({
    $Timer.Stop()
    $Timer.Dispose()
})

$Timer.Start()
[void]$Form.ShowDialog()
$Form.Dispose()
