# Envia os mapas (data/evron/, fora do git) para a release "mapas". Rode so quando eles mudarem.
#   powershell -ExecutionPolicy Bypass -File tools\publicar_mapas.ps1                 envia (precisa do gh autenticado)
#   powershell -ExecutionPolicy Bypass -File tools\publicar_mapas.ps1 -SoEmpacotar    so cria o pacote em %TEMP%\evron_mapas
# ATENCAO: o repositorio e publico; os mapas ficam disponiveis para qualquer pessoa.
param([string]$Dados = (Join-Path (Split-Path $PSScriptRoot -Parent) 'data'), [switch]$SoEmpacotar)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path "$Dados\evron\height_4096x2048.f32")) { throw "nao achei os mapas em $Dados\evron (veja -Dados)" }
$saida = Join-Path $env:TEMP 'evron_mapas'
New-Item -ItemType Directory -Force $saida | Out-Null
$pacote = Join-Path $saida 'Evron-mapas.tar.gz'
$marca = Join-Path $saida 'mapas.version'
Write-Host 'Empacotando (alguns minutos)...'
& "$env:SystemRoot\System32\tar.exe" -czf $pacote -C $Dados evron
if ($LASTEXITCODE) { throw 'nao deu para empacotar' }
Set-Content $marca (Get-FileHash $pacote -Algorithm SHA256).Hash
'{0} ({1:N0} MB)' -f $pacote, ((Get-Item $pacote).Length / 1MB)
if ($SoEmpacotar) { return }
$repo = 'Normandioo/TheOneWhomShallNotBeNamed'
if (@(gh release list -R $repo --json tagName -q '.[].tagName') -notcontains 'mapas') {
    # prerelease: a "mais nova" (latest) continua sendo sempre uma versao do jogo
    gh release create mapas -R $repo --prerelease --title 'Mapas de Evron' --notes 'Baixados pelo atalho dos playtesters.'
    if ($LASTEXITCODE) { throw 'nao deu para criar a release dos mapas' }
}
gh release upload mapas $pacote -R $repo --clobber
if ($LASTEXITCODE) { throw 'o envio dos mapas falhou' }
gh release upload mapas $marca -R $repo --clobber  # por ultimo: so anuncia a versao depois de o pacote estar la
if ($LASTEXITCODE) { throw 'o envio de mapas.version falhou' }
Write-Host 'Mapas publicados.'
