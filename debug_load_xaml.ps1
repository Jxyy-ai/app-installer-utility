Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase

try {
    [xml]$xaml = Get-Content "$PSScriptRoot\MainWindow.xaml" -Raw
    $xr = New-Object System.Xml.XmlNodeReader $xaml
    $w = [System.Windows.Markup.XamlReader]::Load($xr)
    Write-Host 'XAML_LOAD_OK'
}
catch {
    Write-Host 'XAML_LOAD_ERROR'
    Write-Host $_.Exception.Message
    if ($_.Exception.InnerException) { Write-Host 'INNER:'; Write-Host $_.Exception.InnerException.Message }
}
