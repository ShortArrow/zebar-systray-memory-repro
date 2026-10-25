<#
.SYNOPSIS
  Print one tab-separated line per widget report: the time, every Zebar renderer's
  private memory, and what the widget reported (outputs received, outputs
  not freed yet, image bytes received, JS heap). When no report arrives for 5 seconds, as after a
  renderer crash, the line has memory only.

.EXAMPLE
  ./collector.ps1 | Tee-Object results.tsv
#>
param([int]$Port = 47123)

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

function Get-RendererMegabytes {
  $zebar = Get-Process zebar -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $zebar) { return 'zebar not running' }
  $all = Get-CimInstance Win32_Process
  $descendants = [System.Collections.Generic.List[object]]::new()
  $parents = @($zebar.Id)
  while ($parents) {
    $children = @($all | Where-Object { $parents -contains $_.ParentProcessId })
    $descendants.AddRange($children)
    $parents = @($children.ProcessId)
  }
  ($descendants | Where-Object CommandLine -match '--type=renderer' | ForEach-Object {
      [int]((Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue).PrivateMemorySize64 / 1MB)
    }) -join '/'
}

"time`trenderersMB`treport"
$pending = $listener.GetContextAsync()
try {
  while ($true) {
    $report = ''
    if ($pending.Wait(5000)) {
      $context = $pending.Result
      $report = [System.IO.StreamReader]::new($context.Request.InputStream).ReadToEnd()
      $context.Response.AddHeader('Access-Control-Allow-Origin', '*')
      $context.Response.StatusCode = 204
      $context.Response.Close()
      $pending = $listener.GetContextAsync()
    }
    "{0}`t{1}`t{2}" -f (Get-Date -Format HH:mm:ss), (Get-RendererMegabytes), $report
  }
} finally {
  $listener.Stop()
}
