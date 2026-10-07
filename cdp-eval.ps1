# cdp-eval.ps1 - Reads an open browser tab's rendered text over raw CDP (HTTP /json/list +
# WebSocket Runtime.evaluate), without going through Playwright/connectOverCDP. See README.md
# for why this exists and what it does and does not prove.
#
# Usage: powershell -File cdp-eval.ps1 -UrlMatch "example.com" [-Expr "document.body.innerText"] [-Max 4000]
param(
  [Parameter(Mandatory=$true)][string]$UrlMatch,
  [string]$Expr = "document.body.innerText",
  [int]$Max = 4000,
  [int]$Port = 18800,
  [int]$TimeoutMs = 15000
)

$ErrorActionPreference = "Stop"

$list = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 10
$page = $list | Where-Object { $_.type -eq "page" -and $_.url -like "*$UrlMatch*" } | Select-Object -First 1
if (-not $page) { throw "No open tab found with a URL containing '$UrlMatch'" }

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$cts = New-Object System.Threading.CancellationTokenSource($TimeoutMs)
$ws.ConnectAsync([Uri]$page.webSocketDebuggerUrl, $cts.Token).Wait()

$payload = @{
  id = 1
  method = "Runtime.evaluate"
  params = @{ expression = $Expr; returnByValue = $true; awaitPromise = $true }
} | ConvertTo-Json -Depth 5 -Compress

$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$seg = New-Object System.ArraySegment[byte] (,$bytes)
$ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()

$sb = New-Object System.Text.StringBuilder
$buf = New-Object byte[] 65536
do {
  $rseg = New-Object System.ArraySegment[byte] (,$buf)
  $r = $ws.ReceiveAsync($rseg, $cts.Token)
  $r.Wait()
  [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count))
} while (-not $r.Result.EndOfMessage)

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "done", $cts.Token).Wait()

$resp = $sb.ToString() | ConvertFrom-Json
if ($resp.result.exceptionDetails) { throw ("Exception in page: " + $resp.result.exceptionDetails.text) }
$val = [string]$resp.result.result.value
Write-Output ("URL: " + $page.url)
Write-Output ("TITLE: " + $page.title)
Write-Output "--- CONTENT ---"
if ($val.Length -gt $Max) { Write-Output $val.Substring(0, $Max) } else { Write-Output $val }
