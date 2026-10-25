<#
.SYNOPSIS
  Show tray icons that swap their image on a timer, like animated tray apps
  such as PPCpuMon or RunCat365, using a plain WinForms NotifyIcon. The icons
  are removed when -DurationSeconds elapses.
#>
param(
  [int]$Count = 8,
  [int]$IntervalMs = 100,
  [int]$DurationSeconds = 60
)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$script:frames = 0..9 | ForEach-Object {
  $bitmap = [System.Drawing.Bitmap]::new(16, 16)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.Clear([System.Drawing.Color]::FromArgb(255, $_ * 25, 128, 255 - $_ * 25))
  $graphics.Dispose()
  [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
}
$script:icons = 1..$Count | ForEach-Object {
  [System.Windows.Forms.NotifyIcon]@{ Icon = $script:frames[0]; Text = "PoC #$_"; Visible = $true }
}
$script:frame = 0

$animate = [System.Windows.Forms.Timer]@{ Interval = $IntervalMs }
$animate.add_Tick({
    $script:frame++
    foreach ($icon in $script:icons) { $icon.Icon = $script:frames[$script:frame % $script:frames.Count] }
  })
$stop = [System.Windows.Forms.Timer]@{ Interval = $DurationSeconds * 1000 }
$stop.add_Tick({ [System.Windows.Forms.Application]::ExitThread() })

"$Count icons, every $IntervalMs ms, for $DurationSeconds s"
$animate.Start()
$stop.Start()
try {
  [System.Windows.Forms.Application]::Run()
} finally {
  $script:icons | ForEach-Object { $_.Dispose() }
}
