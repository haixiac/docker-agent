[CmdletBinding()]
Param(
    [Parameter(Position=1)]
    [String] $Target = "build",
    [String] $RemotingVersion = '3192.v713e3b_039fb_e',
    [String] $BuildNumber = '1',
    [switch] $DisableEnvProps = $false,
    [switch] $DryRun = $false
)

$ErrorActionPreference = 'Stop'
$Repository = 'agent'
$Organization = 'jenkins'
$ImageType = 'windows-ltsc2019'

if(!$DisableEnvProps) {
    Get-Content env.props | ForEach-Object {
        $items = $_.Split("=")
        if($items.Length -eq 2) {
            $name = $items[0].Trim()
            $value = $items[1].Trim()
            Set-Item -Path "env:$($name)" -Value $value
        }
    }
}

if(![String]::IsNullOrWhiteSpace($env:DOCKERHUB_REPO)) {
    $Repository = $env:DOCKERHUB_REPO
}

if(![String]::IsNullOrWhiteSpace($env:DOCKERHUB_ORGANISATION)) {
    $Organization = $env:DOCKERHUB_ORGANISATION
}

if(![String]::IsNullOrWhiteSpace($env:REMOTING_VERSION)) {
    $RemotingVersion = $env:REMOTING_VERSION
}

if(![String]::IsNullOrWhiteSpace($env:IMAGE_TYPE)) {
    $ImageType = $env:IMAGE_TYPE
}

# Check for required commands
Function Test-CommandExists {
    # From https://devblogs.microsoft.com/scripting/use-a-powershell-function-to-see-if-a-command-exists/
    Param (
        [String] $command
    )

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try {
        if(Get-Command $command){
            Write-Debug "$command exists"
        }
    }
    Catch {
        "$command does not exist"
    }
    Finally {
        $ErrorActionPreference=$oldPreference
    }
}

# this is the jdk version that will be used for the 'bare tag' images, e.g., jdk17-windowsservercore-1809 -> windowsserver-1809
$defaultJdk = '17'
$builds = @{}
$env:REMOTING_VERSION = "$RemotingVersion"

$items = $ImageType.Split("-")
$env:WINDOWS_FLAVOR = $items[0]
$env:WINDOWS_VERSION_TAG = $items[1]
$env:TOOLS_WINDOWS_VERSION = $items[1]
if ($items[1] -eq 'ltsc2019') {
    # There are no eclipse-temurin:*-ltsc2019 or mcr.microsoft.com/powershell:*-ltsc2019 docker images unfortunately, only "1809" ones
    $env:TOOLS_WINDOWS_VERSION = '1809'
}

$ProgressPreference = 'SilentlyContinue' # Disable Progress bar for faster downloads

Test-CommandExists "docker"
Test-CommandExists "docker-compose"
Test-CommandExists "yq"

$baseDockerCmd = 'docker-compose --file=build-windows.yaml'
$baseDockerBuildCmd = '{0} build --parallel --pull' -f $baseDockerCmd

Invoke-Expression "$baseDockerCmd config --services" 2>$null | ForEach-Object {
    $image = '{0}-{1}-{2}' -f $_, $env:WINDOWS_FLAVOR, $env:WINDOWS_VERSION_TAG # Ex: "jdk17-nanoserver-1809"

    # Remove the 'jdk' prefix
    $jdkMajorVersion = $_.Remove(0,3)

    $versionTag = "${RemotingVersion}-${BuildNumber}-${image}"
    $tags = @( $image, $versionTag )

    # Additional image tag without any 'jdk' prefix for the default JDK
    $baseImage = "${env:WINDOWS_FLAVOR}-${env:WINDOWS_VERSION_TAG}"
    if($jdkMajorVersion -eq "$defaultJdk") {
        $tags += $baseImage
        $tags += "${RemotingVersion}-${BuildNumber}-${baseImage}"
    }

    $builds[$image] = @{
        'Tags' = $tags;
    }
}

Write-Host "= PREPARE: List of $Organization/$Repository images and tags to be processed:"
ConvertTo-Json $builds

Write-Host "= BUILD: Building all images..."
if ($DryRun) {
    Write-Host "(dry-run) $baseDockerBuildCmd"
} else {
    Invoke-Expression $baseDockerBuildCmd
}
Write-Host "= BUILD: Finished building all images."

if($lastExitCode -ne 0) {
    exit $lastExitCode
}

function Test-Image {
    param (
        $ImageName
    )

    Write-Host "= TEST: Testing image ${ImageName}:"

    $env:AGENT_IMAGE = $ImageName
    $serviceName = $ImageName.SubString(0, $ImageName.IndexOf('-'))
    $env:BUILD_CONTEXT = Invoke-Expression "$baseDockerCmd config" 2>$null |  yq -r ".services.${serviceName}.build.context"
    $env:VERSION = "$RemotingVersion-$BuildNumber"

    if(Test-Path ".\target\$ImageName") {
        Remove-Item -Recurse -Force ".\target\$ImageName"
    }
    New-Item -Path ".\target\$ImageName" -Type Directory | Out-Null
    $configuration.TestResult.OutputPath = ".\target\$ImageName\junit-results.xml"
    $TestResults = Invoke-Pester -Configuration $configuration
    if ($TestResults.FailedCount -gt 0) {
        Write-Host "There were $($TestResults.FailedCount) failed tests in $ImageName"
        $testFailed = $true
    } else {
        Write-Host "There were $($TestResults.PassedCount) passed tests out of $($TestResults.TotalCount) in $ImageName"
    }
    Remove-Item env:\AGENT_IMAGE
    Remove-Item env:\BUILD_CONTEXT
    Remove-Item env:\VERSION
}

if($target -eq "test") {
    if ($DryRun) {
        Write-Host "= TEST: (dry-run) test harness"
    } else {
        Write-Host "= TEST: Starting test harness"

        # Only fail the run afterwards in case of any test failures
        $testFailed = $false
        $mod = Get-InstalledModule -Name Pester -MinimumVersion 5.3.0 -MaximumVersion 5.3.3 -ErrorAction SilentlyContinue
        if($null -eq $mod) {
            Write-Host "= TEST: Pester 5.3.x not found: installing..."
            $module = "c:\Program Files\WindowsPowerShell\Modules\Pester"
            if(Test-Path $module) {
                takeown /F $module /A /R
                icacls $module /reset
                icacls $module /grant Administrators:'F' /inheritance:d /T
                Remove-Item -Path $module -Recurse -Force -Confirm:$false
            }
            Install-Module -Force -Name Pester -MaximumVersion 5.3.3
        }

        Import-Module Pester
        Write-Host "= TEST: Setting up Pester environment..."
        $configuration = [PesterConfiguration]::Default
        $configuration.Run.PassThru = $true
        $configuration.Run.Path = '.\tests'
        $configuration.Run.Exit = $true
        $configuration.TestResult.Enabled = $true
        $configuration.TestResult.OutputFormat = 'JUnitXml'
        $configuration.Output.Verbosity = 'Diagnostic'
        $configuration.CodeCoverage.Enabled = $false

        Write-Host "= TEST: Testing all images..."
        foreach($image in $builds.Keys) {
            Test-Image $image
        }

        # Fail if any test failures
        if($testFailed -ne $false) {
            Write-Error "Test stage failed!"
            exit 1
        } else {
            Write-Host "= TEST: stage passed!"
        }
    }
}

function Publish-Image {
    param (
        [String] $Build,
        [String] $ImageName
    )
    if ($DryRun) {
        Write-Host "= PUBLISH: (dry-run) docker tag then publish '$Build $ImageName'"
    } else {
        Write-Host "= PUBLISH: Tagging $Build => full name = $ImageName"
        docker tag "$Build" "$ImageName"

        Write-Host "= PUBLISH: Publishing $ImageName..."
        docker push "$ImageName"
    }
}


if($target -eq "publish") {
    # Only fail the run afterwards in case of any issues when publishing the docker images
    $publishFailed = 0
    foreach($b in $builds.Keys) {
        foreach($tag in $Builds[$b]['Tags']) {
            Publish-Image "$b" "${Organization}/${Repository}:${tag}"
            if($lastExitCode -ne 0) {
                $publishFailed = 1
            }
        }
    }

    # Fail if any issues when publising the docker images
    if($publishFailed -ne 0) {
        Write-Error "Publish failed!"
        exit 1
    }
}

if($lastExitCode -ne 0) {
    Write-Error "Build failed!"
} else {
    Write-Host "Build finished successfully"
}
exit $lastExitCode
