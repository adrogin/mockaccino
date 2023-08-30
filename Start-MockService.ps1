function Get-BaseUriFromRequest {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$requestString
    )

    $index = $requestString.IndexOf('?')
    if ($index -gt 0) {
        return $requestString.Substring(0, $index)
    }

    return $requestString
}

function Get-MockContentFilePath {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$path
    )

    if ($path -match '[A-Za-z]:\\*.') {
        return $path
    }
    else {
        return Join-Path $configFolder $path
    }
}

function Get-MockResponse {
    Param(
        [Parameter(Mandatory=$true)]
        [object]$mockResource,
        [string]$method,
        [int]$index
    )

    if($index -ge $mockResource."responses$method".Length) {
        $index = 0
    }

    return $mockResource."responses$method"[$index]
}

function Initialize-MockConfig
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$jsonConfig
    )

    $mockConfig = ConvertFrom-Json $jsonConfig

    foreach($mockResource in $mockConfig.mockResources) {
        foreach($method in $mockResource.allowedMethods) {
            Add-Member -InputObject $mockResource -NotePropertyName "responseIndex$method" -NotePropertyValue 0
            Add-Member -InputObject $mockResource -NotePropertyName "responses$method" -NotePropertyValue @()

            foreach($response in $mockResource.responses) {
                if($response.method -eq $method) {
                    $mockResource."responses$method" += $response
                }
            }
        }
    }

    return $mockConfig
}

function IsMethodAllowedForResource {
    Param(
        [Parameter(Mandatory=$true)]
        [Object]$resource,
        [Parameter(Mandatory=$true)]
        [string]$method
    )

    foreach($allowedMethod in $resource.allowedMethods) {
        if ($method -eq $allowedMethod) {
            return $true
        }
    }

    return $false
}

function Reset-AllEndpoints
{
    Param(
        [Parameter(Mandatory=$true)]
        $mockConfig
    )

    foreach($mockResource in $mockConfig.mockResources) {
        foreach($method in $mockResource.allowedMethods) {
            $mockResource."responseIndex$method" = 0
        }
    }
}

function Set-SuccessResponse
{
    Param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerContext]$context
    )

    $context.Response.StatusCode = 200
    $context.Response.Close()
}

function Set-InternalServerErrorResponse
{
    Param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerContext]$context
    )

    $context.Response.StatusCode = 500
}

function Set-MethodNotAllowedResponse
{
    Param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerContext]$context
    )

    $context.Response.StatusCode = 405
    $context.Response.Close()
}

function Set-NotFoundResponse
{
    Param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerContext]$context
    )

    $context.Response.StatusCode = 404
    $context.Response.Close()
}

function Process-HttpRequest {
    Param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerContext]$context,
        [Parameter(Mandatory=$true)]
        $mockConfig
    )

    $resource = Select-Resource $mockConfig $context.Request.RawUrl
    if ($null -eq $resource) {
        Set-NotFoundResponse $context
    }
    elseif (IsMethodAllowedForResource $resource $context.Request.HttpMethod) {
        Set-Response $context $resource
    }
    else {
        Set-MethodNotAllowedResponse $context
    }
}

function Set-ResponseBody {
    Param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerContext]$context,
        [Parameter(Mandatory=$true)]
        [string]$contentText
    )

    $writer = New-Object System.IO.StreamWriter($context.Response.OutputStream)
    $writer.WriteLine($contentText)
    $writer.Close()
}

function Set-Response {
    Param(
        [Parameter(Mandatory=$true)]
        [System.Net.HttpListenerContext]$context,
        [Parameter(Mandatory=$true)]
        $mockResource
    )

    $index = $mockResource.("responseIndex$($context.Request.HttpMethod)")
    $response = Get-MockResponse $mockResource $context.Request.HttpMethod $index
    if(++$index -ge $mockResource."responses$($context.Request.HttpMethod)".Length) {
        $index = 0
    }
    $mockResource."responseIndex$($context.Request.HttpMethod)" = $index

    $context.Response.StatusCode = $response.statusCode
    switch ($response.contentSource) {
        'inline' {
            Set-ResponseBody $context $response.content
        }
        'file' {
            Set-ResponseBody $context (Get-Content -Raw -Path (Get-MockContentFilePath $response.filePath))
        }
    }

    $context.Response.Close()
}

function Select-Resource {
    Param(
        [Parameter(Mandatory=$true)]
        $mockConfig,

        [Parameter(Mandatory=$true)]
        [string]$requestUri
    )

    $baseUri = Get-BaseUriFromRequest $requestUri
    foreach($resource in $mockConfig.mockResources)
    {
        if ($resource.endpoint -eq $baseUri) {
            return $resource
        }
    }

    return $null
}

function Start-HttpListener {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$jsonConfig
    )

    $mockConfig = Initialize-MockConfig $jsonConfig

    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add($mockConfig.urlPrefix)
        $listener.Start()
    }
    catch {
        throw $_
    }

    [bool]$stopSignal = $false
    Write-Host 'HTTP listener started'

    while (-not $stopSignal)
    {
        $context = $listener.GetContext()

        if ($context.Request.RawUrl -eq '/exit') {
            Write-Host 'Stop signal received'
            Set-SuccessResponse $context
            $stopSignal = $true
        }
        elseif ($context.Request.RawUrl -eq '/reset') {
            Write-Host 'Reset signal received'
            Reset-AllEndpoints $mockConfig
            Set-SuccessResponse $context
        }
        else {
            Process-HttpRequest $context $mockConfig
        }
    }

    $listener.Close()
}

function Start-MockService {
    [CmdletBinding(DefaultParameterSetName = 'FileName')]
    Param(
        [Parameter(Mandatory = $false, ParameterSetName = 'FileName')]
        [string] $configFolder,
        [Parameter(Mandatory = $false, ParameterSetName = 'FileName')]
        [string]$configFileName = "mockServiceConfig.json",

        [Parameter(Mandatory = $false, ParameterSetName = 'JsonContent')]
        [string]$jsonConfig
    )

    if ([string]::IsNullOrEmpty($jsonConfig)) {
        if ([string]::IsNullOrEmpty($configFolder)) {
            $configFolder = Join-Path $PSScriptRoot "MockServiceConfig"
        }

        $jsonConfig = Get-Content -Raw -Path (Join-Path $configFolder $configFileName)
    }

    Start-HttpListener -jsonConfig $jsonConfig
}
