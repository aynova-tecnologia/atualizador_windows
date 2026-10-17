param(
    [Parameter(Mandatory = $true)][int]$ProcessoId,
    [Parameter(Mandatory = $true)][int]$Build,
    [Parameter(Mandatory = $true)][string]$Zip,
    [Parameter(Mandatory = $true)][string]$Instalacao,
    [Parameter(Mandatory = $true)][string]$Exe
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

[Environment]::CurrentDirectory = $Instalacao
Set-Location -LiteralPath $Instalacao

$app = Join-Path $Instalacao 'app'
$anterior = Join-Path $Instalacao 'anterior'
$proxima = Join-Path $Instalacao 'proxima'
$registroDeFalha = Join-Path $Instalacao 'falha.json'
$log = Join-Path $Instalacao 'atualizador.log'
$registroPendente = Join-Path $Instalacao 'pendente.json'

function Registrar([string]$mensagem) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $mensagem" | Add-Content -LiteralPath $log
}

function ComRetentativa([scriptblock]$acao) {
    for ($tentativa = 1; $tentativa -le 20; $tentativa++) {
        try { & $acao; return }
        catch {
            if ($tentativa -eq 20) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}

Remove-Item -LiteralPath $registroPendente -Force -ErrorAction SilentlyContinue

try {
    Registrar "inicio: build $Build, processo $ProcessoId"
    Wait-Process -Id $ProcessoId -Timeout 60 -ErrorAction SilentlyContinue
    if (Get-Process -Id $ProcessoId -ErrorAction SilentlyContinue) { throw 'o app nao fechou em 60 segundos' }

    $outraInstancia = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($app, [StringComparison]::OrdinalIgnoreCase) }
    if ($outraInstancia) { throw 'outra janela do app continua aberta; feche todas e abra de novo' }

    if (Test-Path -LiteralPath $proxima) { ComRetentativa { Remove-Item -LiteralPath $proxima -Recurse -Force } }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $proxima)
    if (-not (Test-Path -LiteralPath (Join-Path $proxima $Exe))) { throw "o pacote nao contem $Exe" }

    if (Test-Path -LiteralPath $anterior) { ComRetentativa { Remove-Item -LiteralPath $anterior -Recurse -Force } }
    ComRetentativa { Rename-Item -LiteralPath $app -NewName 'anterior' }
    try {
        ComRetentativa { Rename-Item -LiteralPath $proxima -NewName 'app' }
    }
    catch {
        Rename-Item -LiteralPath $anterior -NewName 'app'
        throw
    }

    if (Test-Path -LiteralPath $registroDeFalha) { Remove-Item -LiteralPath $registroDeFalha -Force }
    Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
    Registrar "troca concluida: build $Build"
}
catch {
    $erro = "$_"
    Registrar "falha: $erro"
    @{ build = $Build; erro = $erro } | ConvertTo-Json | Set-Content -LiteralPath $registroDeFalha
}

Start-Process -FilePath (Join-Path $app $Exe) -WorkingDirectory $app
