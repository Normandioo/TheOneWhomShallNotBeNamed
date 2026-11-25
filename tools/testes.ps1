# Roda os testes sem nenhuma janela na tela: o Godot nasce escondido e fora da tela, e continua desenhando (as capturas funcionam).
#   powershell -ExecutionPolicy Bypass -File tools\testes.ps1              a bateria inteira
#   powershell -ExecutionPolicy Bypass -File tools\testes.ps1 hub globe    so essas suites
# Os registros e as capturas ficam em %TEMP%\evron_testes. O caminho do Godot pode vir da variavel de ambiente GODOT.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Suites)

$projeto = Split-Path $PSScriptRoot -Parent
$godot = if ($env:GODOT) { $env:GODOT } else { 'E:\Godot-4.7.2-mono\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe' }
if (-not $Suites) { $Suites = Get-ChildItem "$projeto\tests\suites\*_suite.gd" | ForEach-Object { $_.BaseName -replace '_suite$', '' } }
$saida = Join-Path $env:TEMP 'evron_testes'
New-Item -ItemType Directory -Force $saida | Out-Null

$falhas = @()
foreach ($s in $Suites) {
    $log = Join-Path $saida "$s.log"
    $inicio = Get-Date
    $p = Start-Process $godot -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err" -ArgumentList @(
        '--path', "`"$projeto`"", '--position', '-20000,-20000', '-s', 'tests/run_suite.gd', '--', "tests/suites/${s}_suite.gd", "`"$saida`"", 'scene')
    $null = $p.Handle  # sem isto o ExitCode vem vazio
    if ($p.WaitForExit(600000)) { $codigo = $p.ExitCode } else { $p.Kill(); $codigo = 'TEMPO ESGOTADO' }
    $erros = @(Select-String -Path $log, "$log.err" -Pattern 'SCRIPT ERROR|SHADER ERROR')
    $ok = $codigo -eq 0 -and $erros.Count -eq 0
    if (-not $ok) { $falhas += $s }
    '{0,-24} {1,-6} {2,4:N0}s' -f $s, $(if ($ok) { 'ok' } else { 'FALHOU' }), ((Get-Date) - $inicio).TotalSeconds
}
''
if ($falhas) { "$($falhas.Count) de $($Suites.Count) falharam: $($falhas -join ', ') (registros em $saida)"; exit 1 }
"As $($Suites.Count) suites passaram."
