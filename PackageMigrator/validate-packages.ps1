# Set the base URL of your Nexus Repository Manager
$baseUrl = "https://repo.incendium.net"

Do{
    $packageType = Read-Host "Please enter the type of package. Either 'nuget' or 'npm'"
} While ($packageType -notmatch "nuget|npm")

# Set the repository name
Do{
    $repositoryName = Read-Host "Please enter the name of the SonaType repository"
    if($repositoryName -eq "" -or  $null -eq $repositoryName){$voice.speak("Ohne Repo nix los. Gib was ein Brudi.")}
} While ($repositoryName -eq "" -or  $null -eq $repositoryName)

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
        # Say something
        $voice.speak("Ohne Auth wächst kein Kraut. Woher soll der Wissen wer du bist?")
        exit
    }
    if($sonaTypeUsername -eq ""){$sonaTypeUsername = $credentials.sonaType.username}
    if($sonaTypePassword -eq ""){$sonaTypePassword = $credentials.sonaType.password}

    if($gitTeaUsername -eq ""){$gitTeaUsername = $credentials.gitTea.username}
    if($gitTeaPassword -eq ""){$gitTeaPassword = $credentials.gitTea.password}
    if($gitTeaApiKey -eq ""){$gitTeaApiKey = $credentials.gitTea.apiKey}
}

# Convert the credentials to a Base64-encoded string
$nexusBase64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("${sonaTypeUsername}:${sonaTypePassword}")))
# Set nexusHeaders for basic authentication
$nexusHeaders = @{
    Authorization = "Basic $nexusBase64AuthInfo"
}

# Convert the credentials to a Base64-encoded string
$giteaBase64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("${gitTeaUsername}:${gitTeaPassword}")))
# Set nexusHeaders for basic authentication
$giteaHeaders = @{
    Authorization = "Basic $giteaBase64AuthInfo"
}

$continuationToken = $null
$missingPackages = New-Object Collections.Generic.List[string]

try {
    Do {

        # Add a continuation token to the request if one exists
        $parameters = @{
            continuationToken = $continuationToken
        }
    
        # Invoke the REST API to get the list of components
        try {
            if($null -ne $parameters['continuationToken']){
                $response = Invoke-RestMethod -Uri $apiEndpoint -Body $parameters -Method GET -Headers $nexusHeaders
            } else {
                $response = Invoke-RestMethod -Uri $apiEndpoint -Method GET -Headers $nexusHeaders
            }
        }
        catch {
            $exceptionMessage = $_.Exception.Message
            Write-Host "Response unsuccessful. Exception: $exceptionMessage. Terminating"
            $uploadedPackages | ConvertTo-Json | Out-File ($PSScriptRoot + "/uploadedPackages.json")
            # Say something
            $voice.speak("Der Server sagt nein. SonaType kann die Anfrage so nicht nehmen, du keck.")
            exit
        }
    
        $continuationToken = $response.continuationToken
    
        Write-Host "Continuation-Token: $continuationToken"
    
        # Iterate through the components and add them to the dictionary
        foreach ($component in $response.items) {
            $componentName = $component.name
            $componentVersion = $component.version
            $componentEntry = "$componentName $componentVersion"
            Write-Host "Component: $componentEntry"
            
            try {
                Invoke-RestMethod -Uri "https://source.consiliari.de/api/v1/packages/consiliari/nuget/$componentName/$componentVersion" -Method GET -Headers $giteaHeaders
            }
            catch {
                Write-Host "MissingPackage: $componentEntry. Exception: $exceptionMessage."
                $missingPackages.Add($componentEntry)
            }
        }
    } While ($null -ne $continuationToken)
}
catch {
    $exceptionMessage = $_.Exception.Message
    $missingPackages | ConvertTo-Json | Out-File ($PSScriptRoot + "/missingPackages/$repositoryName.json")
    Write-Host "Loop failed. Exception: $exceptionMessage. Terminating"
}

$missingPackages | ConvertTo-Json | Out-File ($PSScriptRoot + "/missingPackages/$repositoryName.json")