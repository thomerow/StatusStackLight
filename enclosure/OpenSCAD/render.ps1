<#
.SYNOPSIS
    Generates the printable parts (STL) and the preview images of the enclosure.

.DESCRIPTION
    Runs entirely through the OpenSCAD command line - the GUI is not opened.
    OpenSCAD writes its messages (including echo()) to stderr; the script
    captures them and only shows the model's echo() lines.

.PARAMETER Only
    All (default) | Stl | Preview

.PARAMETER OpenScad
    Path to openscad.exe, if it is not found automatically.

.PARAMETER Render
    Images from the full CGAL render instead of the preview. Much slower and
    WITHOUT the board ghosts (%), but free of preview artefacts.

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

# Under StrictMode, reading a $LASTEXITCODE that was never set throws.
$global:LASTEXITCODE = 0

$Here       = Split-Path -Parent $PSCommandPath
$Scad       = Join-Path $Here 'statusstacklight_enclosure.scad'
$PreviewDir = Join-Path $Here 'preview'

if (-not (Test-Path $Scad)) { throw "Model not found: $Scad" }

# ---------------------------------------------------------------------------
#  Find openscad.exe
# ---------------------------------------------------------------------------
function Resolve-OpenScad {
    param([string] $Hint)

    $candidates = @()
    if ($Hint) { $candidates += $Hint }
    $inPath = Get-Command openscad.exe -ErrorAction SilentlyContinue
    if ($inPath) { $candidates += $inPath.Source }
    $candidates += @(
        (Join-Path $env:ProgramFiles 'OpenSCAD\openscad.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'OpenSCAD\openscad.exe')
        (Join-Path $env:ProgramFiles 'OpenSCAD (Nightly)\openscad.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\OpenSCAD\openscad.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    throw 'openscad.exe not found - please pass the path with -OpenScad.'
}

$OS = Resolve-OpenScad -Hint $OpenScad
Write-Host "OpenSCAD : $OS"
Write-Host "Model    : $Scad"
Write-Host ''

# ---------------------------------------------------------------------------
#  Call wrapper
# ---------------------------------------------------------------------------
$script:EchoLines = $null

function Invoke-OpenScad {
    param(
        [string]   $Target,
        [string[]] $Defines = @(),
        [string[]] $Extra   = @()
    )

    $arguments = @('-o', $Target)
    foreach ($d in $Defines) { $arguments += @('-D', $d) }
    $arguments += $Extra
    $arguments += $Scad

    # IMPORTANT: openscad.exe is a GUI subsystem binary and returns
    # immediately unless PowerShell consumes its output through a real
    # pipeline. The ForEach-Object forces exactly that - without the pipeline
    # the script moves on before the file has been written.
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $log = @(& $OS @arguments 2>&1 | ForEach-Object { "$_" })
    $code = $global:LASTEXITCODE
    $clock.Stop()

    if ($code -ne 0 -or -not (Test-Path $Target)) {
        $log | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        throw "OpenSCAD failed: $Target"
    }

    # Show the model's echo() output only once per run
    if ($null -eq $script:EchoLines) {
        $script:EchoLines = @($log | Where-Object { "$_" -like 'ECHO:*' })
    }

    # Plausibility check: did the run really rewrite the file?
    $age = (Get-Date) - (Get-Item $Target).LastWriteTime
    if ($age.TotalSeconds -gt 60) {
        throw "$Target was not rewritten - OpenSCAD apparently did not wait."
    }

    $kb = [math]::Round((Get-Item $Target).Length / 1KB)
    '{0,-26} {1,7} kB  {2,6:N1} s' -f (Split-Path $Target -Leaf), $kb, $clock.Elapsed.TotalSeconds |
        Write-Host

    # Pass warnings through - you want to see those
    $log | Where-Object { "$_" -match 'WARNING|ERROR' } |
        ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
}

# ---------------------------------------------------------------------------
#  Printable parts
# ---------------------------------------------------------------------------
if ($Only -in @('All', 'Stl')) {
    Write-Host 'Printable parts (CGAL render):' -ForegroundColor Cyan
    foreach ($part in @('body', 'base')) {
        Invoke-OpenScad -Target (Join-Path $Here "$part.stl") `
                        -Defines @(('part="{0}"' -f $part), 'show_boards=false')
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Preview images
#
#  Camera in gimbal format: --camera=tx,ty,tz,rot_x,rot_y,rot_z,dist
#    rot_x  0 = from above, 90 = horizontal, >90 = from below
#    rot_z    rotation around the vertical axis
#
#  Without 'Dist', --viewall --autocenter determine target and distance.
#  With 'Target' + 'Dist' the camera is fixed - needed for close-ups, because
#  --viewall always zooms out to the whole part. 'Target' is a point in model
#  coordinates (inner coordinates + wall thickness).
# ---------------------------------------------------------------------------
if ($Only -in @('All', 'Preview')) {

    $images = @(
        @{ File = '01_base_iso.png';       Part = 'base';      Ghost = $false; Rot = '55,0,25';   Proj = 'perspective'
           Target = '67,58,2';   Dist = 345 }
        @{ File = '02_usbc_detail.png';    Part = 'both';      Ghost = $true;  Rot = '74,0,-26';  Proj = 'perspective'
           Target = '67,3,6.25'; Dist = 58 }
        @{ File = '03_body_inside.png';    Part = 'body';      Ghost = $false; Rot = '125,0,25';  Proj = 'perspective' }
        @{ File = '04_body_lid_top.png';   Part = 'body';      Ghost = $false; Rot = '0,0,0';     Proj = 'orthogonal'  }
        @{ File = '05_assembled.png';      Part = 'both';      Ghost = $true;  Rot = '55,0,25';   Proj = 'perspective'
           Target = '67,58,17';  Dist = 440 }
        @{ File = '06_exploded.png';       Part = 'explosion'; Ghost = $true;  Rot = '62,0,25';   Proj = 'perspective' }
    )

    if (-not (Test-Path $PreviewDir)) { New-Item -ItemType Directory -Path $PreviewDir | Out-Null }

    $mode = if ($Render) { 'CGAL render, without board ghosts' } else { 'preview' }
    Write-Host "Preview images ($mode):" -ForegroundColor Cyan

    foreach ($img in $images) {
        if ($img.ContainsKey('Dist')) {
            $extra = @("--camera=$($img.Target),$($img.Rot),$($img.Dist)")
        } else {
            $extra = @("--camera=0,0,0,$($img.Rot),0", '--viewall', '--autocenter')
        }
        $extra += @(
            "--imgsize=$Width,$Height"
            "--projection=$($img.Proj)"
            '--colorscheme=Cornfield'
        )
        if ($Render) { $extra += '--render' }

        Invoke-OpenScad -Target (Join-Path $PreviewDir $img.File) `
                        -Defines @(('part="{0}"' -f $img.Part),
                                   ('show_boards={0}' -f $img.Ghost.ToString().ToLower())) `
                        -Extra $extra
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Derived dimensions and collision checks of the model
# ---------------------------------------------------------------------------
if ($script:EchoLines) {
    Write-Host 'Model output:' -ForegroundColor Cyan
    foreach ($line in $script:EchoLines) {
        $text = "$line" -replace '^ECHO:\s*"?', '' -replace '"$', ''
        $color = if ($text -match 'COLLISION|cuts into') { 'Red' } else { 'Gray' }
        Write-Host "  $text" -ForegroundColor $color
    }
}
