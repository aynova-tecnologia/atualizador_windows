$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$origem = $PSScriptRoot
$manifesto = Get-Content -LiteralPath (Join-Path $origem 'versao.json') -Raw | ConvertFrom-Json
$zip = Join-Path $origem $manifesto.zip

$instalacao = Join-Path $env:LOCALAPPDATA (Join-Path 'Agrosepac' $manifesto.nome)
$app = Join-Path $instalacao 'app'
$exe = Join-Path $app $manifesto.exe

Write-Host "Instalando $($manifesto.nome) $($manifesto.versao)+$($manifesto.build)..."

$aberto = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($app, [StringComparison]::OrdinalIgnoreCase) }
if ($aberto) { throw "Feche o $($manifesto.nome) antes de instalar." }

$temporario = Join-Path $env:TEMP "instalar-$($manifesto.build).zip"
Copy-Item -LiteralPath $zip -Destination $temporario -Force
$hash = (Get-FileHash -LiteralPath $temporario -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $manifesto.sha256.ToLower()) { throw 'O pacote na pasta de rede esta corrompido. Avise a TI.' }

New-Item -ItemType Directory -Force -Path $instalacao | Out-Null
if (Test-Path -LiteralPath $app) { Remove-Item -LiteralPath $app -Recurse -Force }
[System.IO.Compression.ZipFile]::ExtractToDirectory($temporario, $app)
Remove-Item -LiteralPath $temporario -Force
New-Item -ItemType File -Force -Path (Join-Path $instalacao '.atualizador') | Out-Null

$shell = New-Object -ComObject WScript.Shell
foreach ($pasta in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
    $atalho = $shell.CreateShortcut((Join-Path $pasta "$($manifesto.nome).lnk"))
    $atalho.TargetPath = $exe
    $atalho.WorkingDirectory = $app
    $atalho.IconLocation = "$exe,0"
    $atalho.Save()
}

# O Windows guarda o icone do atalho num cache indexado pelo caminho do exe, que
# e sempre o mesmo aqui; sem limpar, a barra de tarefas segue com o icone antigo
# depois de trocar o icone do app.
try { Start-Process -FilePath 'ie4uinit.exe' -ArgumentList '-show' -NoNewWindow -Wait -ErrorAction SilentlyContinue } catch {}

Write-Host "Pronto. Abra o $($manifesto.nome) pelo atalho na area de trabalho."
Start-Process -FilePath $exe -WorkingDirectory $app
