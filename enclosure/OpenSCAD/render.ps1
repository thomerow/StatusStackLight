<#
.SYNOPSIS
    Erzeugt die Druckteile (STL) und die Vorschaubilder des Gehaeuses.

.DESCRIPTION
    Laeuft vollstaendig ueber die OpenSCAD-Kommandozeile - die GUI wird nicht
    geoeffnet. OpenSCAD schreibt seine Meldungen (auch echo()) auf stderr;
    das Skript faengt sie ab und zeigt nur die echo()-Zeilen des Modells an.

.PARAMETER Only
    All (Standard) | Stl | Preview

.PARAMETER OpenScad
    Pfad zu openscad.exe, falls er nicht automatisch gefunden wird.

.PARAMETER Render
    Bilder aus dem vollen CGAL-Render statt aus der Vorschau. Deutlich
    langsamer und OHNE die Platinen-Geister (%), dafuer ohne Vorschau-Artefakte.

.EXAMPLE
    .\render.ps1
    .\render.ps1 -Only Preview
    .\render.ps1 -OpenScad "D:\Tools\OpenSCAD\openscad.exe"
#>
[CmdletBinding()]
param(
    [ValidateSet('All', 'Stl', 'Preview')]
    [string]   $Only     = 'All',
    [string]   $OpenScad,
    [switch]   $Render,
    [int]      $Width    = 1600,
    [int]      $Height   = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Unter StrictMode wirft ein noch nie gesetztes $LASTEXITCODE beim Lesen.
$global:LASTEXITCODE = 0

$Here       = Split-Path -Parent $PSCommandPath
$Scad       = Join-Path $Here 'statusstacklight_gehaeuse.scad'
$PreviewDir = Join-Path $Here 'preview'

if (-not (Test-Path $Scad)) { throw "Modell nicht gefunden: $Scad" }

# ---------------------------------------------------------------------------
#  openscad.exe finden
# ---------------------------------------------------------------------------
function Resolve-OpenScad {
    param([string] $Hint)

    $kandidaten = @()
    if ($Hint) { $kandidaten += $Hint }
    $imPfad = Get-Command openscad.exe -ErrorAction SilentlyContinue
    if ($imPfad) { $kandidaten += $imPfad.Source }
    $kandidaten += @(
        (Join-Path $env:ProgramFiles 'OpenSCAD\openscad.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'OpenSCAD\openscad.exe')
        (Join-Path $env:ProgramFiles 'OpenSCAD (Nightly)\openscad.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\OpenSCAD\openscad.exe')
    )
    foreach ($k in $kandidaten) {
        if ($k -and (Test-Path $k)) { return (Resolve-Path $k).Path }
    }
    throw 'openscad.exe nicht gefunden - Pfad bitte per -OpenScad angeben.'
}

$OS = Resolve-OpenScad -Hint $OpenScad
Write-Host "OpenSCAD : $OS"
Write-Host "Modell   : $Scad"
Write-Host ''

# ---------------------------------------------------------------------------
#  Aufruf-Wrapper
# ---------------------------------------------------------------------------
$script:EchoZeilen = $null

function Invoke-OpenScad {
    param(
        [string]   $Ziel,
        [string[]] $Defines = @(),
        [string[]] $Extra   = @()
    )

    $argumente = @('-o', $Ziel)
    foreach ($d in $Defines) { $argumente += @('-D', $d) }
    $argumente += $Extra
    $argumente += $Scad

    # WICHTIG: openscad.exe ist ein GUI-Subsystem-Binary und kehrt sofort
    # zurueck, wenn PowerShell die Ausgabe nicht ueber eine echte Pipeline
    # konsumiert. Das ForEach-Object erzwingt genau das - ohne die Pipeline
    # laeuft das Skript weiter, bevor die Datei geschrieben ist.
    $uhr = [System.Diagnostics.Stopwatch]::StartNew()
    $log = @(& $OS @argumente 2>&1 | ForEach-Object { "$_" })
    $code = $global:LASTEXITCODE
    $uhr.Stop()

    if ($code -ne 0 -or -not (Test-Path $Ziel)) {
        $log | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        throw "OpenSCAD ist fehlgeschlagen: $Ziel"
    }

    # echo()-Ausgabe des Modells nur einmal pro Lauf zeigen
    if ($null -eq $script:EchoZeilen) {
        $script:EchoZeilen = @($log | Where-Object { "$_" -like 'ECHO:*' })
    }

    # Plausibilitaetskontrolle: hat der Lauf die Datei wirklich neu geschrieben?
    $alter = (Get-Date) - (Get-Item $Ziel).LastWriteTime
    if ($alter.TotalSeconds -gt 60) {
        throw "$Ziel wurde nicht neu geschrieben - OpenSCAD hat offenbar nicht gewartet."
    }

    $kb = [math]::Round((Get-Item $Ziel).Length / 1KB)
    '{0,-26} {1,7} kB  {2,6:N1} s' -f (Split-Path $Ziel -Leaf), $kb, $uhr.Elapsed.TotalSeconds |
        Write-Host

    # Warnungen durchreichen - die will man sehen
    $log | Where-Object { "$_" -match 'WARNING|ERROR' } |
        ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
}

# ---------------------------------------------------------------------------
#  Druckteile
# ---------------------------------------------------------------------------
if ($Only -in @('All', 'Stl')) {
    Write-Host 'Druckteile (CGAL-Render):' -ForegroundColor Cyan
    foreach ($teil in @('body', 'boden')) {
        Invoke-OpenScad -Ziel (Join-Path $Here "$teil.stl") `
                        -Defines @(('teil="{0}"' -f $teil), 'zeige_platinen=false')
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Vorschaubilder
#
#  Kamera im Gimbal-Format: --camera=tx,ty,tz,rot_x,rot_y,rot_z,dist
#    rot_x  0 = von oben, 90 = waagerecht, >90 = von unten
#    rot_z    Drehung um die Hochachse
#
#  Ohne 'Dist' uebernimmt --viewall --autocenter Zielpunkt und Abstand.
#  Mit 'Ziel' + 'Dist' wird die Kamera fest gesetzt - noetig fuer Nahaufnahmen,
#  weil --viewall immer auf das gesamte Teil herauszoomt. 'Ziel' ist ein Punkt
#  in Modellkoordinaten (Innenkoordinaten + Wandstaerke).
# ---------------------------------------------------------------------------
if ($Only -in @('All', 'Preview')) {

    $bilder = @(
        @{ Datei = '01_boden_iso.png';         Teil = 'boden';     Ghost = $false; Rot = '55,0,25';   Proj = 'perspective'
           Ziel = '67,58,2';   Dist = 345 }
        @{ Datei = '02_usbc_detail.png';       Teil = 'beides';    Ghost = $true;  Rot = '74,0,-26';  Proj = 'perspective'
           Ziel = '67,3,6.25'; Dist = 58 }
        @{ Datei = '03_body_innenansicht.png'; Teil = 'body';      Ghost = $false; Rot = '125,0,25';  Proj = 'perspective' }
        @{ Datei = '04_body_deckel_oben.png';  Teil = 'body';      Ghost = $false; Rot = '0,0,0';     Proj = 'orthogonal'  }
        @{ Datei = '05_montiert.png';          Teil = 'beides';    Ghost = $true;  Rot = '55,0,25';   Proj = 'perspective'
           Ziel = '67,58,17';  Dist = 440 }
        @{ Datei = '06_explosion.png';         Teil = 'explosion'; Ghost = $true;  Rot = '62,0,25';   Proj = 'perspective' }
    )

    if (-not (Test-Path $PreviewDir)) { New-Item -ItemType Directory -Path $PreviewDir | Out-Null }

    $modus = if ($Render) { 'CGAL-Render, ohne Platinen-Geister' } else { 'Vorschau' }
    Write-Host "Vorschaubilder ($modus):" -ForegroundColor Cyan

    foreach ($b in $bilder) {
        if ($b.ContainsKey('Dist')) {
            $extra = @("--camera=$($b.Ziel),$($b.Rot),$($b.Dist)")
        } else {
            $extra = @("--camera=0,0,0,$($b.Rot),0", '--viewall', '--autocenter')
        }
        $extra += @(
            "--imgsize=$Width,$Height"
            "--projection=$($b.Proj)"
            '--colorscheme=Cornfield'
        )
        if ($Render) { $extra += '--render' }

        Invoke-OpenScad -Ziel (Join-Path $PreviewDir $b.Datei) `
                        -Defines @(('teil="{0}"' -f $b.Teil),
                                   ('zeige_platinen={0}' -f $b.Ghost.ToString().ToLower())) `
                        -Extra $extra
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Abgeleitete Masse und Kollisionspruefungen des Modells
# ---------------------------------------------------------------------------
if ($script:EchoZeilen) {
    Write-Host 'Modellausgabe:' -ForegroundColor Cyan
    foreach ($z in $script:EchoZeilen) {
        $text = "$z" -replace '^ECHO:\s*"?', '' -replace '"$', ''
        $farbe = if ($text -match 'KOLLISION|schneidet') { 'Red' } else { 'Gray' }
        Write-Host "  $text" -ForegroundColor $farbe
    }
}
