# windows-devshell.ps1
# Install WSL (if needed) and enter Nix development shell

function Write-Info($msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Write-Success($msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Write-Error($msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

function Write-Warning($msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Test-Admin {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if WSL is installed
Write-Info "Checking WSL installation..."
$wslInstalled = $false
try {
    $wslCheck = wsl --status 2>&1
    if ($LASTEXITCODE -eq 0) {
        $wslInstalled = $true
        Write-Success "WSL is already installed"
    }
} catch {}

# Check if a distro is installed
$distroInstalled = $false
if ($wslInstalled) {
    Write-Info "Checking WSL distributions..."
    try {
        $distros = wsl --list --quiet 2>$null
        if ($distros) {
            $distroInstalled = $true
            Write-Success "WSL distribution found"
        }
    } catch {}
}

# If WSL or distro is missing, we need admin to install
if (-not $wslInstalled -or -not $distroInstalled) {
    if (-not (Test-Admin)) {
        Write-Error "WSL setup requires Administrator privileges."
        Write-Info "Please run PowerShell as Administrator for first-time setup."
        exit 1
    }
}

# Install WSL if not present
if (-not $wslInstalled) {
    Write-Info "Installing WSL..."

    Write-Info "Enabling WSL feature..."
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null

    Write-Info "Enabling Virtual Machine Platform..."
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null

    Write-Info "Downloading WSL2 kernel update..."
    $kernelUrl = "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi"
    $kernelInstaller = "$env:TEMP\wsl_update_x64.msi"
    try {
        Invoke-WebRequest -Uri $kernelUrl -OutFile $kernelInstaller -UseBasicParsing
    } catch {
        Write-Warning "Could not download WSL2 kernel update. Will try to continue..."
    }

    if (Test-Path $kernelInstaller) {
        Write-Info "Installing WSL2 kernel update..."
        Start-Process -FilePath msiexec.exe -ArgumentList "/i", $kernelInstaller, "/quiet", "/norestart" -Wait
    }

    Write-Info "Setting WSL default version to 2..."
    wsl --set-default-version 2 2>$null

    Write-Info "Installing WSL core..."
    wsl --install --no-distribution

    Write-Success "WSL installed. You may need to restart your computer."
    Write-Info "Please restart and run this script again."
    exit 0
}

# Install Ubuntu if no distro
if (-not $distroInstalled) {
    Write-Info "No WSL distribution found. Installing Ubuntu..."
    wsl --install -d Ubuntu --no-launch

    Write-Info "Waiting for Ubuntu installation to complete..."
    $maxAttempts = 60
    $attempt = 0
    while ($attempt -lt $maxAttempts) {
        Start-Sleep -Seconds 5
        $attempt++
        try {
            $distros = wsl --list --quiet 2>$null
            if ($distros) {
                break
            }
        } catch {}
        Write-Info "Waiting... ($attempt/$maxAttempts)"
    }

    if (-not $distros) {
        Write-Error "Ubuntu installation timed out. Please check WSL status manually."
        exit 1
    }
    Write-Success "Ubuntu installed"
}

# Check if a distro is installed
Write-Info "Checking WSL distributions..."
$distros = @()
try {
    $distros = wsl --list --quiet 2>$null
} catch {}

if (-not $distros) {
    Write-Info "No WSL distribution found. Installing Ubuntu..."
    wsl --install -d Ubuntu --no-launch

    # Wait for installation
    Write-Info "Waiting for Ubuntu installation to complete..."
    $maxAttempts = 60
    $attempt = 0
    while ($attempt -lt $maxAttempts) {
        Start-Sleep -Seconds 5
        $attempt++
        try {
            $distros = wsl --list --quiet 2>$null
            if ($distros) {
                break
            }
        } catch {}
        Write-Info "Waiting... ($attempt/$maxAttempts)"
    }

    if (-not $distros) {
        Write-Error "Ubuntu installation timed out. Please check WSL status manually."
        exit 1
    }
    Write-Success "Ubuntu installed"
} else {
    Write-Success "WSL distribution found"
}

# Create the linux-devshell script inside WSL
Write-Info "Preparing linux-devshell script..."

$linuxDevShellBase64 = "@LINUX_DEVSHELL_BASE64@"

$wslTempPath = "/tmp/windows-devshell.sh"
$psTempPath = wsl wslpath -w $wslTempPath

# Decode base64 and write to temp file
$decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($linuxDevShellBase64))
Set-Content -Path $psTempPath -Value $decoded -Encoding UTF8 -NoNewline

# Make it executable and run
Write-Info "Running linux-devshell inside WSL..."
Write-Info "This will install Nix (if needed) and enter the development shell."
Write-Host ""

wsl -e bash -c "chmod +x $wslTempPath && exec $wslTempPath"
