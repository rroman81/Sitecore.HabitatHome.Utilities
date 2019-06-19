Param(
    [string] $ConfigurationFile = ".\configuration-xp0.json",
    [string] $LogFolder = ".\logs\",
    [string] $LogFileName = "install-sitecoredemo.log",
    [string] $devSitecoreUsername,
    [securestring] $devSitecorePassword
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$StopWatch = New-Object -TypeName System.Diagnostics.Stopwatch 
$StopWatch.Start()
#####################################################
# 
#  Install Modules
# 
#####################################################
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$LogFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFolder) 
if (!(Test-Path $LogFolder)) {
    New-item -ItemType Directory -Path $LogFolder
}
$LogFile = Join-path $LogFolder $LogFileName
if (Test-Path $LogFile) {
    Get-Item $LogFile | Remove-Item
}

if (!(Test-Path $ConfigurationFile)) {
    Write-Host "Configuration file '$($ConfigurationFile)' not found." -ForegroundColor Red
    Write-Host  "Please use 'set-installation...ps1' files to generate a configuration file." -ForegroundColor Red
    Exit 1
}
$config = Get-Content -Raw $ConfigurationFile |  ConvertFrom-Json
if (!$config) {
    throw "Error trying to load configuration!"
}  
$assets = $config.assets
$modules = $config.modules
$site = $config.settings.site
$sitecore = $config.settings.sitecore
$solr = $config.settings.solr
$sql = $config.settings.sql
$xConnect = $config.settings.xConnect
$sharedResourcePath = Join-Path $assets.sharedUtilitiesRoot "assets\configuration"
$downloadFolder = $assets.packageRepository
$packagesFolder = (Join-Path $downloadFolder "modules")

$loginSession = $null

if (!(Test-Path $packagesFolder)) {
    New-Item $packagesFolder -ItemType Directory -Force  > $null  
}
Function Install-SitecoreInstallFramework {
    if ((Get-PSRepository | Where-Object {$_.Name -eq $assets.psRepositoryName}).count -eq 0) {
        Register-PSRepository -Name $assets.psRepositoryName -SourceLocation $assets.psRepository -InstallationPolicy Trusted 
    }

    #Sitecore Install Framework dependencies
    Import-Module WebAdministration
    
    #Install SIF
    $sifVersion = $assets.installerVersion
    
    $module = Get-Module -FullyQualifiedName @{ModuleName = "SitecoreInstallFramework"; ModuleVersion = $sifVersion }
    if (-not $module) {
        write-host "Installing the Sitecore Install Framework, version $($assets.installerVersion)" -ForegroundColor Green
        Install-Module SitecoreInstallFramework -Repository $assets.psRepositoryName -RequiredVersion $sifVersion -Scope CurrentUser -Force
        Import-Module SitecoreInstallFramework -Force
    }
}
Function Get-SitecoreCredentials{
    
    if ($null -eq $global:credentials) {
        if ([string]::IsNullOrEmpty($devSitecoreUsername)) {
            $global:credentials = Get-Credential -Message "Please provide dev.sitecore.com credentials"
        }
        elseif (![string]::IsNullOrEmpty($devSitecoreUsername) -and ![string]::IsNullOrEmpty($devSitecorePassword)) {
            $secpasswd = ConvertTo-SecureString $devSitecorePassword -AsPlainText -Force
            $global:credentials = New-Object System.Management.Automation.PSCredential ($devSitecoreUsername, $secpasswd)
        }
        else {
            throw "Credentials required for download"
        }
    }
    $user = $global:credentials.GetNetworkCredential().UserName
    $password = $global:credentials.GetNetworkCredential().Password

    Invoke-RestMethod -Uri https://dev.sitecore.net/api/authorization -Method Post -ContentType "application/json" -Body "{username: '$user', password: '$password'}" -SessionVariable loginSession -UseBasicParsing 
    $global:loginSession = $loginSession
    
}

Function Install-Modules {

    $bootLoaderPackagePath = [IO.Path]::Combine( $assets.sitecoreazuretoolkit, "resources\9.1.0\Addons\Sitecore.Cloud.Integration.Bootload.wdp.zip")
    $bootloaderConfigurationOverride = $([io.path]::combine($assets.sharedUtilitiesRoot, "assets", 'Sitecore.Cloud.Integration.Bootload.InstallJob.exe.config'))
    $bootloaderInstallationPath = $([io.path]::combine($site.webRoot, $site.hostName, "App_Data\tools\InstallJob"))
    $assetsJson = (Resolve-Path $ConfigurationFile) 

    $params = @{
        Path                            = (Join-Path $sharedResourcePath "install-single-module.json")
        SharedConfigurationPath         = $sharedResourcePath
        AssetsJson                      = $assetsJson
        ModuleId                        = "sd"
        LoginSession                    = $global:loginSession 
        SiteName                        = $site.hostName
        WebRoot                         = $site.webRoot
        XConnectSiteName                = $xConnect.siteName
        SqlServer                       = $sql.server
        SqlAdminUser                    = $sql.adminUser 
        SqlAdminPassword                = $sql.adminPassword
        DatabasePrefix                  = $site.prefix
        SecurityUserName                = $sql.securityUser
        SecurityUserPassword            = $sql.SecurityPassword
        CoreUserName                    = $sql.coreUser
        CoreUserPassword                = $sql.corePassword
        MasterUserName                  = $sql.masterUser
        MasterUserPassword              = $sql.MasterPassword
        BootLoaderPackagePath           = $bootLoaderPackagePath
        BootloaderConfigurationOverride = $bootloaderConfigurationOverride
        BootloaderInstallationPath      = $bootloaderInstallationPath
        SitecoreAdminPassword           = $sitecore.adminPassword
    }
    Push-Location $sharedResourcePath
    Install-SitecoreConfiguration @params -Verbose
    Pop-Location
   
}

Import-Module (Join-Path $assets.sharedUtilitiesRoot "assets\modules\SharedInstallationUtilities\SharedInstallationUtilities.psm1") -Force
Install-SitecoreInstallFramework
Get-SitecoreCredentials
Install-Modules
$StopWatch.Stop()
$StopWatch
