[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$trialPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Experimental-Overclock-VRR-Trial.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $trialPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) {
    throw 'The guarded-trial source did not parse.'
}
$definition = @(
    $ast.FindAll(
        {
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'New-ProtectedRuntimeAcl'
        },
        $true
    )
)
if ($definition.Count -ne 1) {
    throw "Expected one New-ProtectedRuntimeAcl definition; found $($definition.Count)."
}
Invoke-Expression $definition[0].Extent.Text

$first = New-ProtectedRuntimeAcl
$second = New-ProtectedRuntimeAcl
if ([object]::ReferenceEquals($first, $second)) {
    throw 'The ACL factory reused one DirectorySecurity object.'
}

$usersSid = 'S-1-5-32-545'
$requiredReadRights = [Security.AccessControl.FileSystemRights]::ReadAndExecute
$writeRights =
    [Security.AccessControl.FileSystemRights]::WriteData -bor
    [Security.AccessControl.FileSystemRights]::AppendData -bor
    [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
    [Security.AccessControl.FileSystemRights]::WriteAttributes -bor
    [Security.AccessControl.FileSystemRights]::Delete -bor
    [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
    [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
    [Security.AccessControl.FileSystemRights]::TakeOwnership

foreach ($acl in @($first, $second)) {
    if (-not $acl.AreAccessRulesProtected) {
        throw 'A generated protected-runtime ACL still permits inherited access rules.'
    }
    $usersAllowRights = [Security.AccessControl.FileSystemRights]0
    foreach ($rule in @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))) {
        if ($rule.IdentityReference.Value -eq $usersSid -and
            $rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow) {
            $usersAllowRights = $usersAllowRights -bor $rule.FileSystemRights
        }
    }
    if (($usersAllowRights -band $requiredReadRights) -ne $requiredReadRights) {
        throw 'The generated ACL is missing standard-user read and execute rights.'
    }
    if (($usersAllowRights -band $writeRights) -ne 0) {
        throw 'The generated ACL grants standard-user write rights.'
    }
}

[pscustomobject]@{
    Result = 'PASS'
    DistinctAclObjects = $true
    StandardUserReadExecute = $true
    StandardUserWrite = $false
}
