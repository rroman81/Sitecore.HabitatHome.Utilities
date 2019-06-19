param (
    [string]$mygetServer = "https://sitecore.myget.org/F/sc-powershell/api/v2"
)

$gallery = Get-PSRepository|Where-Object {$_.Name -eq "SitecoreGallery"} 

if (!$gallery) {
    Register-PSRepository -Name SitecoreGallery -SourceLocation $mygetServer -PublishLocation $mygetServer -InstallationPolicy Trusted
}
elseif (($gallery.SourceLocation -ne $mygetServer) -or ($gallery.PublishLocation -ne $mygetServer) -or !$gallery.Trusted) {
    Set-PSRepository -Name SitecoreGallery -SourceLocation $mygetServer -PublishLocation $mygetServer -InstallationPolicy Trusted
}

Get-PSRepository -Name "SitecoreGallery" | Format-List * -Force
