# Atalho dos playtesters (Windows): baixa a versao mais nova do jogo, e os mapas quando mudam, e abre o Evron.
# Sem internet ou com falha no download, abre a versao ja instalada. O mundo do jogador fica em %APPDATA%, fora daqui.
$ErrorActionPreference = 'Stop'
$base = if ($env:EVRON_URL) { $env:EVRON_URL } else { 'https://github.com/Normandioo/TheOneWhomShallNotBeNamed/releases' }
$raiz = $PSScriptRoot
$jogo = Join-Path $raiz 'jogo'
$antigo = Join-Path $raiz 'jogo.antigo'
$temp = Join-Path $raiz 'baixando'
$mundo = Join-Path $env:APPDATA 'Godot\app_userdata\Evron'

function Get-Texto($url) {
    $t = & curl.exe -fsL --connect-timeout 10 $url
    if ($LASTEXITCODE) { throw "sem acesso a $url" }
    "$t".Trim()
}

# Baixa o pacote e extrai em $destino; qualquer falha para antes de tocar no que esta instalado.
function Get-Pacote($url, $destino) {
    New-Item -ItemType Directory -Force $temp, $destino | Out-Null
    $arquivo = Join-Path $temp 'pacote.tar.gz'
    & curl.exe -fL --connect-timeout 10 --retry 2 -o $arquivo $url
    if ($LASTEXITCODE) { throw "o download falhou: $url" }
    & "$env:SystemRoot\System32\tar.exe" -xzf $arquivo -C $destino
    if ($LASTEXITCODE) { throw 'o pacote veio com defeito' }
    Remove-Item $arquivo
}

function Get-Instalada($arquivo) { if (Test-Path $arquivo) { (Get-Content $arquivo -Raw).Trim() } else { '' } }

# Uma troca interrompida no meio deixa os mapas na pasta antiga: devolve antes de tudo.
function Restore-Mapas {
    if ((Test-Path "$antigo\data") -and (Test-Path $jogo) -and -not (Test-Path "$jogo\data")) { Move-Item "$antigo\data" "$jogo\data" }
}

try {
    if ((Test-Path $antigo) -and -not (Test-Path $jogo)) { Rename-Item $antigo 'jogo' }
    Restore-Mapas
    if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }

    $nova = Get-Texto "$base/latest/download/versao.txt"
    if ($nova -ne (Get-Instalada "$jogo\versao.txt")) {
        Write-Host 'Baixando a versao nova do jogo...'
        Get-Pacote "$base/latest/download/Evron-windows.tar.gz" "$temp\jogo"
        # Uma versao nova pode converter o banco: guarda uma copia do mundo antes (ficam as 5 ultimas).
        if (Test-Path "$mundo\evron_world.db") {
            $copia = Join-Path $mundo ('copias-atualizacao\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
            New-Item -ItemType Directory -Force $copia | Out-Null
            foreach ($f in 'evron_world.db', 'evron_world.db-wal', 'evron_world.json', 'evron_world.json.bak') {
                if (Test-Path "$mundo\$f") { Copy-Item "$mundo\$f" $copia }
            }
            Get-ChildItem "$mundo\copias-atualizacao" -Directory | Sort-Object Name -Descending | Select-Object -Skip 5 | Remove-Item -Recurse -Force
        }
        Set-Content "$temp\jogo\versao.txt" $nova
        if (Test-Path $antigo) { Remove-Item $antigo -Recurse -Force }
        if (Test-Path $jogo) { Rename-Item $jogo 'jogo.antigo' }  # falha com o jogo aberto, sem mudar nada
        Move-Item "$temp\jogo" $jogo
        Restore-Mapas
        if (Test-Path $antigo) { Remove-Item $antigo -Recurse -Force }
    }

    $mapas = Get-Texto "$base/download/mapas/mapas.version"
    $marca = "$jogo\data\mapas.version"
    if ($mapas -ne (Get-Instalada $marca)) {
        Write-Host 'Baixando os mapas (e grande; so quando eles mudam)...'
        Get-Pacote "$base/download/mapas/Evron-mapas.tar.gz" "$temp\mapas"
        if (-not (Test-Path "$temp\mapas\evron")) { throw 'o pacote dos mapas veio sem a pasta evron' }
        New-Item -ItemType Directory -Force "$jogo\data" | Out-Null
        if (Test-Path "$jogo\data\evron") { Remove-Item "$jogo\data\evron" -Recurse -Force }
        Move-Item "$temp\mapas\evron" "$jogo\data\evron"
        Set-Content $marca $mapas
    }
} catch {
    Write-Warning "Nao deu para atualizar: $($_.Exception.Message)"
    Restore-Mapas
    if (-not (Test-Path "$jogo\Evron.exe") -or -not (Test-Path "$jogo\data\evron")) {
        Write-Host 'Nao ha uma versao completa instalada. Confira a internet e tente de novo.'
        exit 1
    }
    Write-Host 'Abrindo a versao ja instalada.'
}
if (Test-Path $temp) { Remove-Item $temp -Recurse -Force }
if (-not $env:EVRON_NAO_ABRIR) { Start-Process "$jogo\Evron.exe" -WorkingDirectory $jogo }
exit 0
