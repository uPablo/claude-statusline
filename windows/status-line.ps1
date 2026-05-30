# claude-statusline — native Windows (PowerShell) status line for Claude Code
# Mirrors the bash version. Run with:  pwsh -NoProfile -File status-line.ps1
# Reads the Claude Code JSON payload on stdin, prints up to 4 colored lines.

$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture  # '.' decimals

$raw = [Console]::In.ReadToEnd()
try { $j = $raw | ConvertFrom-Json } catch { $j = $null }

# --- Colors ---
$E = [char]27
function Col($n) { "$E[38;5;${n}m" }
$C_CTX=Col 39; $C_5H=Col 214; $C_WK=Col 170; $C_OPUS=Col 135; $C_SONNET=Col 73
$C_COST=Col 42; $C_MEM=Col 75; $C_DISK=Col 80; $C_EFFORT=Col 141
$C_ADD=Col 78; $C_DEL=Col 203; $C_WARN=Col 208; $C_OK=Col 42; $C_LANG=Col 113; $C_BURN=Col 215
$DIM="$E[2m"; $R="$E[0m"
$BAR=6
$ISEP=" $DIM·$R "
$WD=@('dom','seg','ter','qua','qui','sex','sáb')

# --- Safe nested getter ---
function Get-P($obj, [string[]]$path) {
  $cur = $obj
  foreach ($k in $path) { if ($null -eq $cur) { return $null }; $cur = $cur.$k }
  if ($cur -is [string] -and $cur -eq '') { return $null }
  return $cur
}

# --- Helpers ---
function Make-Bar($pct, $color) {
  $p = [int][math]::Round([double]$pct)
  if ($p -gt 100) { $p = 100 }; if ($p -lt 0) { $p = 0 }
  $filled = [int][math]::Floor(($p * $BAR + 50) / 100); if ($filled -gt $BAR) { $filled = $BAR }
  $empty = $BAR - $filled
  $bar = ('▰' * $filled) + ('▱' * $empty)
  "$DIM▕$R$color$bar$R$DIM▏$R"
}
function Seg($label, $color, $pct, $suffix) {
  $p = [int][math]::Round([double]$pct)
  $chunk = "$color$label$R$(Make-Bar $pct $color)$p%"
  if ($suffix) { $chunk += " $DIM$suffix$R" }
  $chunk
}
function To-Epoch($v) {
  if ($null -eq $v -or "$v" -eq '') { return $null }
  if ("$v" -match '^\d+$') { $n = [long]$v; if ($n -gt 100000000000) { $n = [long]($n / 1000) }; return $n }
  try { return [DateTimeOffset]::Parse("$v").ToUnixTimeSeconds() } catch { return $null }
}
function Reset-Label($v) {
  $epoch = To-Epoch $v
  if ($null -eq $epoch) { return '' }
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $diff = [long]$epoch - $now; if ($diff -lt 0) { $diff = 0 }
  $d = [math]::Floor($diff / 86400); $h = [math]::Floor(($diff % 86400) / 3600); $m = [math]::Floor(($diff % 3600) / 60)
  if ($d -gt 0) { $eta = "${d}d${h}h" } elseif ($h -gt 0) { $eta = "${h}h${m}m" } else { $eta = "${m}m" }
  $loc = [DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime
  if ($diff -lt 86400) { $abs = $loc.ToString('HH:mm') }
  else { $abs = "$($WD[[int]$loc.DayOfWeek]) $($loc.ToString('HH:mm'))" }
  "↻$eta · $abs"
}
function Human($n) {
  $n = [double]$n
  if ($n -ge 1e6) { $v = $n / 1e6; if ($v -eq [math]::Floor($v)) { "{0}M" -f [int]$v } else { "{0:0.0}M" -f $v } }
  elseif ($n -ge 1000) { "{0:0}k" -f ($n / 1000) } else { "{0:0}" -f $n }
}
function Gib($b) { "{0:0.0}G" -f ([double]$b / 1GB) }
function Fmt-Dur($s) { $h = [math]::Floor($s / 3600); $m = [math]::Floor(($s % 3600) / 60); if ($h -gt 0) { "${h}h${m}m" } else { "${m}m" } }

# --- Payload fields ---
$cwd        = Get-P $j @('workspace','current_dir'); if (-not $cwd) { $cwd = Get-P $j @('cwd') }
$model      = Get-P $j @('model','display_name'); if (-not $model) { $model = Get-P $j @('model') }
$session_id = Get-P $j @('session_id')
$ctx_pct    = Get-P $j @('context_window','used_percentage')
$ctx_size   = Get-P $j @('context_window','context_window_size')
$cost       = Get-P $j @('cost','total_cost_usd')
$dur_ms     = Get-P $j @('cost','total_duration_ms')
$ladd       = Get-P $j @('cost','total_lines_added')
$ldel       = Get-P $j @('cost','total_lines_removed')
$ccver      = Get-P $j @('version')
$ostyle     = Get-P $j @('output_style','name')
$vimmode    = Get-P $j @('vim','mode')
$effort     = Get-P $j @('effort','level')

$cu = Get-P $j @('context_window','current_usage')
$ctx_tokens = $null; $cache_read = $null
if ($cu -is [double] -or $cu -is [int] -or $cu -is [long]) { $ctx_tokens = [long]$cu }
elseif ($cu) {
  $ctx_tokens = [long]($cu.input_tokens + $cu.output_tokens + $cu.cache_creation_input_tokens + $cu.cache_read_input_tokens)
  $cache_read = $cu.cache_read_input_tokens
}

# effort fallback + account from ~/.claude
if (-not $effort) { try { $effort = (Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw | ConvertFrom-Json).effortLevel } catch {} }
$account = $null; try { $account = (Get-Content "$env:USERPROFILE\.claude.json" -Raw | ConvertFrom-Json).oauthAccount.emailAddress } catch {}

$tmp = $env:TEMP

# --- Session wall-clock ---
$dur = ''
if ($session_id) {
  $sf = Join-Path $tmp "cc-sl-sess-$session_id"
  if (-not (Test-Path $sf)) { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() | Out-File $sf }
  $start = [long](Get-Content $sf -ErrorAction SilentlyContinue)
  if ($start) { $dur = Fmt-Dur ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $start) }
} elseif ($dur_ms) { $dur = Fmt-Dur ([long]$dur_ms / 1000) }

# --- ccusage burn rate + daily (cached 60s) ---
$burn = ''; $daily = ''
$ccCache = Join-Path $tmp 'cc-sl-ccusage.txt'
$ccAge = 99999
if (Test-Path $ccCache) { $ccAge = ((Get-Date) - (Get-Item $ccCache).LastWriteTime).TotalSeconds }
if ($ccAge -gt 60 -and (Get-Command ccusage -ErrorAction SilentlyContinue)) {
  try { $burn = ((ccusage blocks --active --json | ConvertFrom-Json).blocks[0].burnRate.costPerHour) } catch {}
  try { $dd = (ccusage daily --json | ConvertFrom-Json).daily; $daily = ($dd | Sort-Object date | Select-Object -Last 1).totalCost } catch {}
  "$burn`n$daily" | Out-File $ccCache
} elseif (Test-Path $ccCache) {
  $lines = Get-Content $ccCache; $burn = $lines[0]; $daily = $lines[1]
}

# --- System: memory / disk / battery / cpu ---
$mem_pct = ''; $mem_label = ''
try {
  $os = Get-CimInstance Win32_OperatingSystem
  $t = [double]$os.TotalVisibleMemorySize * 1024; $f = [double]$os.FreePhysicalMemory * 1024
  if ($t -gt 0) { $u = $t - $f; $mem_pct = [int][math]::Round($u / $t * 100); $mem_label = "$(Gib $u)/$(Gib $t)" }
} catch {}

$disk_pct = ''; $disk_label = ''
try {
  $d = Get-PSDrive ($env:SystemDrive.TrimEnd(':'))
  $tot = $d.Used + $d.Free
  if ($tot -gt 0) { $disk_pct = [int][math]::Round($d.Used / $tot * 100); $disk_label = "$(Gib $d.Free) free" }
} catch {}

$bat_pct = ''; $bat_chg = ''; $bat_col = $C_OK
try {
  $b = Get-CimInstance Win32_Battery | Select-Object -First 1
  if ($b) {
    $bat_pct = [int]$b.EstimatedChargeRemaining
    if ($b.BatteryStatus -eq 2) { $bat_chg = '⚡' }   # 2 = AC / charging
    if ($bat_pct -lt 50) { $bat_col = $C_5H }; if ($bat_pct -lt 20) { $bat_col = $C_DEL }
  }
} catch {}

$cpu = ''; $cpu_col = $C_OK
try {
  $load = [int]((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average)
  $cpu = "$load%"
  if ($load -ge 90) { $cpu_col = $C_DEL } elseif ($load -ge 70) { $cpu_col = $C_5H }
} catch {}

# --- Language detection (run binaries if present; cached per dir) ---
function Compute-Langs($dir) {
  if (-not $dir) { return '' }
  $out = @()
  function VC($emoji, $ver) { if ($ver) { "$emoji $C_LANG$ver$R" } else { "$emoji" } }
  if ((Test-Path "$dir\package.json") -or (Test-Path "$dir\.nvmrc") -or (Test-Path "$dir\node_modules")) {
    $v = (& node -v 2>$null); if ($v) { $v = $v.TrimStart('v') }; $out += VC '⬢' $v
  }
  if ((Test-Path "$dir\composer.json") -or (Test-Path "$dir\artisan") -or (Get-ChildItem "$dir\*.php" -ErrorAction SilentlyContinue)) {
    $v = (& php -r 'echo PHP_VERSION;' 2>$null); $out += VC '🐘' $v
  }
  if ((Test-Path "$dir\pyproject.toml") -or (Test-Path "$dir\requirements.txt") -or (Test-Path "$dir\.python-version")) {
    $v = ((& python -V 2>&1) -replace 'Python ', ''); $out += VC '🐍' $v
  }
  if (Test-Path "$dir\go.mod") { $v = (((& go version 2>$null) -split ' ')[2] -replace '^go', ''); $out += VC '🐹' $v }
  if (Test-Path "$dir\Cargo.toml") { $v = ((& rustc --version 2>$null) -split ' ')[1]; $out += VC '🦀' $v }
  if ((Test-Path "$dir\Gemfile") -or (Test-Path "$dir\.ruby-version")) { $v = ((& ruby -v 2>$null) -split ' ')[1]; $out += VC '💎' $v }
  if (Test-Path "$dir\deno.json") { $v = ((& deno --version 2>$null | Select-Object -First 1) -split ' ')[1]; $out += VC '🦕' $v }
  ($out -join '  ')
}
$langline = ''
if ($cwd) {
  $key = [System.BitConverter]::ToString(([System.Security.Cryptography.SHA1]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($cwd)))).Replace('-', '').Substring(0, 12)
  $lc = Join-Path $tmp "cc-sl-lang-$key.txt"
  $age = 99999; if (Test-Path $lc) { $age = ((Get-Date) - (Get-Item $lc).LastWriteTime).TotalSeconds }
  if ($age -gt 600) { (Compute-Langs $cwd) | Out-File $lc }
  $langline = (Get-Content $lc -Raw -ErrorAction SilentlyContinue); if ($langline) { $langline = $langline.TrimEnd("`r", "`n") }
}

# --- Identity + git ---
$ident = ''
if ($cwd) { $ident = Split-Path $cwd -Leaf }
$branch = ''; $gitstate = ''; $repo = ''
if ($cwd -and (git -C "$cwd" rev-parse --is-inside-work-tree 2>$null)) {
  $branch = (git -C "$cwd" symbolic-ref --short HEAD 2>$null); if (-not $branch) { $branch = (git -C "$cwd" rev-parse --short HEAD 2>$null) }
  $changed = (git -C "$cwd" status --porcelain 2>$null | Measure-Object -Line).Lines
  $ahead = (git -C "$cwd" rev-list --count '@{u}..HEAD' 2>$null)
  $behind = (git -C "$cwd" rev-list --count 'HEAD..@{u}' 2>$null)
  $stash = (git -C "$cwd" stash list 2>$null | Measure-Object -Line).Lines
  $gdir = (git -C "$cwd" rev-parse --absolute-git-dir 2>$null)
  $gst = ''
  if ((Test-Path "$gdir\rebase-merge") -or (Test-Path "$gdir\rebase-apply")) { $gst = 'REBASE' }
  elseif (Test-Path "$gdir\MERGE_HEAD") { $gst = 'MERGE' }
  elseif (Test-Path "$gdir\CHERRY_PICK_HEAD") { $gst = 'CHERRY' }
  $origin = (git -C "$cwd" remote get-url origin 2>$null)
  if ($origin) { $repo = ($origin -replace '\.git$', '') -replace '.*[/:]([^/]+/[^/]+)$', '$1' }
  if ($gst) { $gitstate = "$C_DEL$gst$R " }
  if ($changed -gt 0) { $gitstate += "$C_WARN●$changed$R" } else { $gitstate += "$C_OK✓$R" }
  if ($ahead -gt 0) { $gitstate += " $DIM↑$ahead$R" }
  if ($behind -gt 0) { $gitstate += " $DIM↓$behind$R" }
  if ($stash -gt 0) { $gitstate += " $DIM⚑$stash$R" }
}
if ($branch) {
  if ($ident) { $ident += "${DIM}:$R" }
  $ident += $branch
  if ($gitstate) { $ident += " $gitstate" }
  if ($repo) { $ident += " $DIM($repo)$R" }
}

# --- Assemble lines ---
$L1 = $ident
if ($langline) { $L1 += "$ISEP$langline" }
if (($ladd -gt 0) -or ($ldel -gt 0)) {
  $L1 += "$ISEP$C_ADD+$(Human ([int]$ladd))$R$DIM/$R$C_DEL-$(Human ([int]$ldel))$R"
}

$p2 = @()
if ($model)  { $p2 += "$model" }
if ($effort) { $p2 += "${DIM}think:$R$C_EFFORT$effort$R" }
if ($cost -ne $null) { $p2 += "$C_COST`$$('{0:0.00}' -f [double]$cost)$R" }
if ($burn)   { $p2 += "$C_BURN`$$('{0:0.0}' -f [double]$burn)/h$R" }
if ($daily)  { $p2 += "${DIM}day $R$C_COST`$$('{0:0}' -f [double]$daily)$R" }
if ($dur)    { $p2 += "$DIM⏱$dur$R" }
$chips = @(); if ($ostyle -and $ostyle -ne 'default') { $chips += $ostyle }; if ($vimmode) { $chips += $vimmode }; if ($ccver) { $chips += "v$ccver" }
if ($chips.Count) { $p2 += "$DIM$($chips -join ' ')$R" }
$L2 = ($p2 -join $ISEP)

$ctx_suffix = ''
if ($ctx_pct -ne $null) {
  if (-not $ctx_tokens -and $ctx_size) { $ctx_tokens = [long]([double]$ctx_pct / 100 * [double]$ctx_size) }
  if ($ctx_tokens -and $ctx_size) { $ctx_suffix = "$(Human $ctx_tokens)/$(Human $ctx_size)" }
  if ($cache_read -and $ctx_tokens -gt 0) { $ctx_suffix += " cache$([int][math]::Round([double]$cache_read / $ctx_tokens * 100))%" }
}
$p3 = @()
if ($ctx_pct -ne $null) { $p3 += (Seg 'ctx' $C_CTX $ctx_pct $ctx_suffix) }
$r5  = Get-P $j @('rate_limits','five_hour','used_percentage')
$r7  = Get-P $j @('rate_limits','seven_day','used_percentage')
$ro  = Get-P $j @('rate_limits','seven_day_opus','used_percentage')
$rs  = Get-P $j @('rate_limits','seven_day_sonnet','used_percentage')
if ($r5 -ne $null) { $p3 += (Seg '5h' $C_5H $r5 (Reset-Label (Get-P $j @('rate_limits','five_hour','resets_at')))) }
if ($r7 -ne $null) { $p3 += (Seg 'wk' $C_WK $r7 (Reset-Label (Get-P $j @('rate_limits','seven_day','resets_at')))) }
if ($ro -ne $null) { $p3 += (Seg 'opus' $C_OPUS $ro (Reset-Label (Get-P $j @('rate_limits','seven_day_opus','resets_at')))) }
if ($rs -ne $null) { $p3 += (Seg 'sonnet' $C_SONNET $rs (Reset-Label (Get-P $j @('rate_limits','seven_day_sonnet','resets_at')))) }
$L3 = ($p3 -join $ISEP)

$p4 = @()
if ($mem_pct -ne '')  { $p4 += (Seg 'mem' $C_MEM $mem_pct $mem_label) }
if ($disk_pct -ne '') { $p4 += (Seg 'disk' $C_DISK $disk_pct $disk_label) }
if ($bat_pct -ne '')  { $p4 += "${DIM}bat$R $bat_col$bat_pct%$bat_chg$R" }
if ($cpu -ne '')      { $p4 += "${DIM}cpu$R $cpu_col$cpu$R" }
$p4 += "$DIM$((Get-Date).ToString('HH:mm'))$R"
if ($account)         { $p4 += "$DIM$account$R" }
$L4 = ($p4 -join $ISEP)

# --- Emit non-empty lines ---
$lines = @($L1, $L2, $L3, $L4) | Where-Object { $_ -ne '' }
Write-Output ($lines -join "`n")
