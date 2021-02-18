[string]$rootFolder = Get-Location

function Get-MockContentFilePath {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$path
    )

    if ($path -match '[A-Za-z]:\\*.') {
        return $path
    }
    else {
        return Join-Path $rootFolder $path
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

function Init-MockConfig
{
    Param(
        [Parameter(Mandatory=$true)]
        [string]$configFile
    )

    $mockConfig = (Get-Content -Raw -Path $configFile | ConvertFrom-Json)

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
    if ($resource -eq $null) {
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

    foreach($resource in $mockConfig.mockResources)
    {
        if ($resource.rawUri -eq $requestUri) {
            return $resource
        }
    }

    return $null
}

function Start-HttpListener {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$configFile,
        [Parameter(Mandatory=$false)]
        [string]$mockRootFolder
    )

    $mockConfig = Init-MockConfig $configFile
    if ($mockRootFolder -ne '') {
        $rootFolder = $mockRootFolder
    }

    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add($mockConfig.urlPrefix)
        $listener.Start()
    }
    catch {
        throw $_
    }

    [bool]$stopSignal = $false

    while (-not $stopSignal)
    {
        $context = $listener.GetContext()

        if ($context.Request.RawUrl -eq '/exit') {
            Set-SuccessResponse $context
            $stopSignal = $true
        }
        else {
            Process-HttpRequest $context $mockConfig
        }
    }

    $listener.Stop()
    $listener.Dispose()
}
