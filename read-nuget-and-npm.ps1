# Set the base URL of your Nexus Repository Manager
$baseUrl = "https://repo.incendium.net"

# Set the repository name
$repositoryName = Read-Host "Please enter the name of the SonaType repository"
if($repositoryName -eq "") {$repositoryName = "nuget-hosted"}

# Set the REST API endpoint for listing components
$apiEndpoint = "$baseUrl/service/rest/v1/components?repository=$repositoryName"

Write-Host "API-Endpoint: $apiEndpoint"

# Set your Nexus credentials
$username = Read-Host "Please enter the username"
$password = Read-Host "Please enter the name of the SonaType repository"

if($username -eq "" -or $password -eq "") {
    $credentials = Get-Content -Path ($PSScriptRoot + "/credentials.json") | ConvertFrom-Json
    if($null -eq $credentials){
        Write-Host "No credentials. Terminating"
        exit
    }
    $username = $credentials.username
    $password = $credentials.password
}

# Convert password to a secure string
$secpasswd = ConvertTo-SecureString $password -AsPlainText -Force

# Create a credential object
$credential = New-Object System.Management.Automation.PSCredential ($username, $secpasswd)

$continuationToken = $null
$duplicateFound = $false
$componentDictionary = @{}

Do {

    # Invoke the REST API to get the list of components
    $parameters = @{
        continuationToken = $continuationToken
    }

    if($null -ne $parameters['continuationToken']){
        $response = Invoke-RestMethod -Uri $apiEndpoint -Credential $credential -Body $parameters -Method Get
    } else {
        $response = Invoke-RestMethod -Uri $apiEndpoint -Credential $credential -Method Get
    }
    
    $continuationToken = $response.continuationToken

    Write-Host "Continuation-Token: $continuationToken"

    # Iterate through the components and display their names
    foreach ($component in $response.items) {
        $componentName = $component.name
        $componentVersion = $component.version
        $componentEntry = "$componentName $componentVersion"
        Write-Host "Component: $componentEntry"
        if (-not $componentDictionary.ContainsKey($component.id)){
            $componentDictionary[$component.id] = $componentEntry
        } else {
            $duplicateFound = $true
            Write-Host "Duplicate found: $componentEntry"
            break
        }
    }

    if ($componentDictionary.Count -ge 20) {
        Write-Host "Limit reached. Breaking"
        break
    }

} While ($null -ne $continuationToken -and $duplicateFound -ne $true)

$componentsFound = $componentDictionary.Count
Write-Host "Found Components: $componentsFound"
