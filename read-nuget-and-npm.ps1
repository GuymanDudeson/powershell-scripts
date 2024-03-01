# Set the base URL of your Nexus Repository Manager
$baseUrl = "https://repo.incendium.net"

Do{
    $packageType = Read-Host "Please enter the type of package. Either 'nuget' or 'npm'"
} While ($packageType -notmatch "nuget|npm")

# Set the repository name
$repositoryName = Read-Host "Please enter the name of the SonaType repository"
if($null -eq $repositoryName){
    Write-Host "No repository. Terminating"
    exit
}

# Set the REST API endpoint for listing components
$apiEndpoint = "$baseUrl/service/rest/v1/components?repository=$repositoryName"

Write-Host "Using ApiEndpoint: $apiEndpoint`n"

# Set your Sonatype credentials
$sonaTypeUsername = Read-Host "Please enter your SonaType username"
$sonaTypePassword = Read-Host -MaskInput "Please enter your SonaType password"
Write-Host "`n"

# Set your GitTea credentials
$gitTeaUsername = Read-Host "Please enter your GitTea username"
$gitTeaPassword = Read-Host -MaskInput "Please enter your GitTea password"
$gitTeaApiKey = Read-Host -MaskInput "Please enter your GitTea ApiKey"
Write-Host "`n"

# Try to load fallback credentials from file
if($sonaTypeUsername -eq "" -or $sonaTypePassword -eq "" -or $gitTeaUsername -eq "" -or $gitTeaPassword -eq "" -or $gitTeaApiKey -eq "") {
    $credentials = Get-Content -Path ($PSScriptRoot + "/credentials.json") | ConvertFrom-Json
    if($null -eq $credentials){
        Write-Host "No credentials. Terminating"
        exit
    }
    if($sonaTypeUsername -eq ""){$sonaTypeUsername = $credentials.sonaType.username}
    if($sonaTypePassword -eq ""){$sonaTypePassword = $credentials.sonaType.password}

    if($gitTeaUsername -eq ""){$gitTeaUsername = $credentials.gitTea.username}
    if($gitTeaPassword -eq ""){$gitTeaPassword = $credentials.gitTea.password}
    if($gitTeaApiKey -eq ""){$gitTeaApiKey = $credentials.gitTea.apiKey}
}

# Check if a nuget source is already created and create one if not
if($packageType -eq "nuget"){
    $existingNugetSources = dotnet nuget list source

    $sourceExists = $false
    foreach ($line in $existingNugetSources){
        if($line.Contains("[Enabled]")) {
            if($line.Contains($repositoryName)){
                $sourceExists = $true
            }
        }        
    }

    if($sourceExists -eq $false){
        $passw = ConvertTo-SecureString $gitTeaPassword -AsPlainText -Force
        try {
            dotnet nuget add source --name $repositoryName --username $gitTeaUsername --password $passw https://source.consiliari.de/api/packages/consiliari/nuget/index.json
        }
        catch {
            $exceptionMessage = $_.Exception.Message
            Write-Host "Source could not be created. $exceptionMessage"
            exit
        }
    }
}

# Convert the credentials to a Base64-encoded string
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("${sonaTypeUsername}:${sonaTypePassword}")))
# Set headers for basic authentication
$headers = @{
    Authorization = "Basic $base64AuthInfo"
}

# Load all already uploaded Packages
if(Test-Path ($PSScriptRoot + "/uploadedPackages.json")){
    $uploadedPackages = Get-Content -Path ($PSScriptRoot + "/uploadedPackages.json") | ConvertFrom-Json
    $uploadedPackages = [System.Collections.Generic.List[string]]$uploadedPackages
}
else {
    $uploadedPackages = New-Object Collections.Generic.List[string];
}

# Create temp directory if not existing
if(-not (Test-Path ($PSScriptRoot + "/tempPackages"))){
    New-Item -Path $PSScriptRoot -name "tempPackages" -ItemType "directory"
}

$continuationToken = $null
$currentNpmScope = ""

try {
    Do {

        # Add a continuation token to the request if one exists
        $parameters = @{
            continuationToken = $continuationToken
        }
    
        # Invoke the REST API to get the list of components
        try {
            if($null -ne $parameters['continuationToken']){
                $response = Invoke-RestMethod -Uri $apiEndpoint -Body $parameters -Method GET -Headers $headers
            } else {
                $response = Invoke-RestMethod -Uri $apiEndpoint -Method GET -Headers $headers
            }
        }
        catch {
            $exceptionMessage = $_.Exception.Message
            Write-Host "Response unsuccessful. Exception: $exceptionMessage. Terminating"
            $uploadedPackages | ConvertTo-Json | Out-File ($PSScriptRoot + "/uploadedPackages.json")
            exit
        }
    
        $continuationToken = $response.continuationToken
    
        Write-Host "Continuation-Token: $continuationToken"
    
        # Iterate through the components and add them to the dictionary
        foreach ($component in $response.items) {
    
            $componentName = $component.name
            $componentVersion = $component.version
            $componentDownloadLink = $component.assets.downloadUrl
            $componentEntry = "$componentName $componentVersion"
            Write-Host "Component: $componentEntry"
    
            # If the package was already uploaded, skip it
            if ($uploadedPackages.Contains($component.id)){
                continue
            } else {
               $uploadedPackages.Add($component.id)
            }
            
            $fileExtension = $packageType -eq "nuget" ? "nupkg" : "tgz" 
            $packageFileName = "$componentName.$componentVersion.$fileExtension"
            $filePath = ($PSScriptRoot + "/tempPackages/$packageFileName")
    
            Invoke-WebRequest $componentDownloadLink -OutFile $filePath -Headers $headers
    
            #Download Package, upload it to GitTea, delete local Package
            if($packageType -eq "nuget"){
                dotnet nuget push $filePath --source $repositoryName -k $gitTeaApiKey
            } elseif ($packageType -eq "npm") {
                $npmName = $component.assets.npm.name
                $packageScope = $npmName.Contains("@") ? $component.assets.npm.name.Split('/')[0] : ""
    
                if($packageScope -ne $currentNpmScope){
                    $currentNpmScope = $packageScope
    
                    if($currentNpmScope -ne ""){
                        $scopedRegistry = "$currentNpmScope" + ":registry"
                        npm config set $scopedRegistry https://source.consiliari.de/api/packages/consiliari/npm/
                        npm config set -- '//source.consiliari.de/api/packages/consiliari/npm/:_authToken' "$gitTeaApiKey"
                    } else {
                        npm config set registry https://source.consiliari.de/api/packages/consiliari/npm/
                        npm config set -- '//source.consiliari.de/api/packages/consiliari/npm/:_authToken' "$gitTeaApiKey"
                    }
                    
                    npm publish $filePath
                }
            }
            
            Remove-Item -Path $filePath
        }
    
        # Safety limit
        #if ($uploadedPackages.Count -ge 10) {
        #    Write-Host "Limit reached. Breaking"
        #    break
        #}
    
        # Wait between every batch of packages to prevent ip block
        Start-Sleep -seconds 2
        Write-Host "`nNext page`n"
    
    } While ($null -ne $continuationToken -and $duplicateFound -ne $true)
}
catch {
    $exceptionMessage = $_.Exception.Message
    Write-Host "Loop failed. Exception: $exceptionMessage. Terminating"
}

$componentsUploaded = $uploadedPackages.Count
Write-Host "Found Components: $componentsUploaded"

$uploadedPackages | ConvertTo-Json | Out-File ($PSScriptRoot + "/uploadedPackages.json")