function Start-MockServiceInNewProcess {
    Param(
        [Parameter(Mandatory=$false)]
        [string] $configFolder,
        [Parameter(Mandatory=$false)]
        [string]$configFileName = "mockServiceConfig.json"
    )

    if([string]::IsNullOrEmpty($configFolder)) {
        $configFolder = Join-Path ($PSScriptRoot) "MockServiceConfig"
    }

    $modulePath = (Get-Module mockaccino).Path
    Start-Process PowerShell -argumentList "-noexit -command `"Import-Module `"$modulePath`"; Start-MockService`""
}
