function Start-MockServiceInBcContainer {
    Param(
        [string]$containerName = $ENV:CONTAINERNAME
    )

    $scriptPath = Join-Path $PSScriptRoot 'Invoke-MockService.ps1'
    $configPath = Join-Path $PSScriptRoot 'MockServiceConfig\mockServiceConfig.json'

    $args = @{
        jsonConfig = Get-Content $configPath -Raw
    }

    $scriptText = (Get-Content $scriptPath -Raw) + "`n" + "Start-MockService"
    Write-Verbose $scriptText
    $scriptBlock = [ScriptBlock]::Create(".{$scriptText}")

    Invoke-ScriptInBCContainer -containerName $containerName -scriptBlock $scriptBlock -argumentList $args
}
