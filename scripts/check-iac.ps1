[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Get-HclBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Content,
        [Parameter(Mandatory = $true)]
        [string] $HeaderPattern,
        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    $header = [regex]::Match($Content, $HeaderPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if (-not $header.Success) {
        throw "Required Terraform block '$Description' was not found."
    }

    $openingBrace = $Content.IndexOf('{', $header.Index + $header.Length - 1)
    if ($openingBrace -lt 0) {
        throw "Terraform block '$Description' has no opening brace."
    }

    $depth = 0
    $inString = $false
    for ($index = $openingBrace; $index -lt $Content.Length; $index++) {
        $character = $Content[$index]

        if ($inString) {
            if ($character -eq '\') {
                $index++
                continue
            }
            if ($character -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($character -eq '"') {
            $inString = $true
            continue
        }

        if ($character -eq '#') {
            $newline = $Content.IndexOf("`n", $index)
            if ($newline -lt 0) {
                break
            }
            $index = $newline
            continue
        }

        if ($character -eq '/' -and $index + 1 -lt $Content.Length -and $Content[$index + 1] -eq '/') {
            $newline = $Content.IndexOf("`n", $index)
            if ($newline -lt 0) {
                break
            }
            $index = $newline
            continue
        }

        if ($character -eq '{') {
            $depth++
        }
        elseif ($character -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Content.Substring($header.Index, $index - $header.Index + 1)
            }
        }
    }

    throw "Terraform block '$Description' is not balanced."
}

function Assert-Pattern {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Content,
        [Parameter(Mandatory = $true)]
        [string] $Pattern,
        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    if (-not [regex]::IsMatch($Content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)) {
        throw "Governance check failed: $Description"
    }
}

foreach ($tool in @('terraform', 'trivy')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required check tool '$tool' is not installed or is not on PATH."
    }
}

Push-Location $repoRoot
try {
    $providerConfig = Get-Content -Raw 'providers.tf'
    $terraformConfig = Get-Content -Raw 'main.tf'
    $variablesConfig = Get-Content -Raw 'variables.tf'
    $terraformFiles = Get-ChildItem -Path $repoRoot -Filter '*.tf' -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\\/]\.terraform[\\/]' }
    $allTerraform = ($terraformFiles | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"

    $tagVariable = Get-HclBlock -Content $variablesConfig -HeaderPattern 'variable\s+"tags"\s*\{' -Description 'tags variable'
    foreach ($requiredTag in @('project', 'managed_by', 'owner', 'data_classification')) {
        Assert-Pattern -Content $tagVariable -Pattern "(?m)^\s*$requiredTag\s*=" -Description "baseline tag '$requiredTag' is configured"
    }

    $localsBlock = Get-HclBlock -Content $terraformConfig -HeaderPattern 'locals\s*\{' -Description 'locals'
    Assert-Pattern -Content $localsBlock -Pattern '(?m)^\s*environment\s*=\s*var\.environment\s*$' -Description 'environment tag is merged into the common tag map'

    $taggedResources = @(
        @{ Header = 'resource\s+"azurerm_resource_group"\s+"main"\s*\{'; Name = 'resource group' }
        @{ Header = 'resource\s+"azurerm_log_analytics_workspace"\s+"main"\s*\{'; Name = 'Log Analytics workspace' }
        @{ Header = 'resource\s+"azurerm_application_insights"\s+"main"\s*\{'; Name = 'Application Insights' }
        @{ Header = 'resource\s+"azurerm_storage_account"\s+"func"\s*\{'; Name = 'Function storage account' }
        @{ Header = 'resource\s+"azurerm_service_plan"\s+"flex"\s*\{'; Name = 'Function service plan' }
        @{ Header = 'resource\s+"azurerm_cosmosdb_account"\s+"audit"\s*\{'; Name = 'Cosmos DB account' }
        @{ Header = 'resource\s+"azurerm_key_vault"\s+"main"\s*\{'; Name = 'Key Vault' }
        @{ Header = 'resource\s+"azurerm_function_app_flex_consumption"\s+"mcp_server"\s*\{'; Name = 'Function App' }
    )
    foreach ($resource in $taggedResources) {
        $resourceBlock = Get-HclBlock -Content $terraformConfig -HeaderPattern $resource.Header -Description $resource.Name
        Assert-Pattern -Content $resourceBlock -Pattern '(?m)^\s*tags\s*=\s*local\.merged_tags\s*$' -Description "$($resource.Name) applies the shared governance tags"
    }

    $providerBlock = Get-HclBlock -Content $providerConfig -HeaderPattern 'provider\s+"azurerm"\s*\{' -Description 'AzureRM provider'
    Assert-Pattern -Content $providerBlock -Pattern '(?m)^\s*storage_use_azuread\s*=\s*true\s*$' -Description 'AzureRM storage operations use Entra ID'

    $functionApp = Get-HclBlock -Content $terraformConfig -HeaderPattern 'resource\s+"azurerm_function_app_flex_consumption"\s+"mcp_server"\s*\{' -Description 'Function App'
    Assert-Pattern -Content $functionApp -Pattern '(?m)^\s*https_only\s*=\s*true\s*$' -Description 'Function App enforces HTTPS'
    $functionIdentity = Get-HclBlock -Content $functionApp -HeaderPattern 'identity\s*\{' -Description 'Function App identity'
    Assert-Pattern -Content $functionIdentity -Pattern '(?m)^\s*type\s*=\s*"SystemAssigned"\s*$' -Description 'Function App uses system-assigned managed identity'

    $storageAccount = Get-HclBlock -Content $terraformConfig -HeaderPattern 'resource\s+"azurerm_storage_account"\s+"func"\s*\{' -Description 'Function storage account'
    Assert-Pattern -Content $storageAccount -Pattern '(?m)^\s*shared_access_key_enabled\s*=\s*false\s*$' -Description 'storage shared-key authentication is disabled'
    Assert-Pattern -Content $storageAccount -Pattern '(?m)^\s*allow_nested_items_to_be_public\s*=\s*false\s*$' -Description 'public blob access is disabled'

    $cosmosAccount = Get-HclBlock -Content $terraformConfig -HeaderPattern 'resource\s+"azurerm_cosmosdb_account"\s+"audit"\s*\{' -Description 'Cosmos DB account'
    Assert-Pattern -Content $cosmosAccount -Pattern '(?m)^\s*local_authentication_enabled\s*=\s*false\s*$' -Description 'Cosmos DB local/key authentication is disabled'

    $keyVault = Get-HclBlock -Content $terraformConfig -HeaderPattern 'resource\s+"azurerm_key_vault"\s+"main"\s*\{' -Description 'Key Vault'
    Assert-Pattern -Content $keyVault -Pattern '(?m)^\s*rbac_authorization_enabled\s*=\s*true\s*$' -Description 'Key Vault authorization uses Azure RBAC'

    $functionPrincipal = 'azurerm_function_app_flex_consumption\.mcp_server\.identity\[0\]\.principal_id'
    $keyVaultRole = Get-HclBlock -Content $terraformConfig -HeaderPattern 'resource\s+"azurerm_role_assignment"\s+"func_kv_secrets_user"\s*\{' -Description 'Function Key Vault role assignment'
    Assert-Pattern -Content $keyVaultRole -Pattern 'role_definition_name\s*=\s*"Key Vault Secrets User"' -Description 'Function receives the Key Vault secrets-reader role'
    Assert-Pattern -Content $keyVaultRole -Pattern "principal_id\s*=\s*$functionPrincipal" -Description 'Key Vault role is assigned to the Function managed identity'

    $cosmosRole = Get-HclBlock -Content $terraformConfig -HeaderPattern 'resource\s+"azurerm_cosmosdb_sql_role_assignment"\s+"func_cosmos_data_contributor"\s*\{' -Description 'Function Cosmos DB role assignment'
    Assert-Pattern -Content $cosmosRole -Pattern "principal_id\s*=\s*$functionPrincipal" -Description 'Cosmos DB data role is assigned to the Function managed identity'

    $storageRole = Get-HclBlock -Content $terraformConfig -HeaderPattern 'resource\s+"azurerm_role_assignment"\s+"func_storage_blob_data_owner"\s*\{' -Description 'Function storage role assignment'
    Assert-Pattern -Content $storageRole -Pattern 'role_definition_name\s*=\s*"Storage Blob Data Owner"' -Description 'Function receives the Storage Blob Data Owner role required by Flex host storage'
    Assert-Pattern -Content $storageRole -Pattern "principal_id\s*=\s*$functionPrincipal" -Description 'Storage role is assigned to the Function managed identity'

    Write-Output 'Terraform security and governance assertions passed.'

    if ($providerConfig -notmatch 'required_version\s*=\s*">=\s*1\.8\.0"') {
        throw 'Terraform configuration must require Terraform >= 1.8.0.'
    }
    if ($providerConfig -notmatch 'azurerm\s*=\s*\{(?s:.*?)version\s*=\s*"~>\s*4\.') {
        throw 'AzureRM must remain constrained to the v4 provider series.'
    }
    if ($terraformConfig -notmatch 'sku_name\s*=\s*"FC1"' -or $terraformConfig -match 'sku_name\s*=\s*"Y1"') {
        throw 'Use the current Flex Consumption FC1 plan; do not introduce legacy Y1.'
    }
    if ($terraformConfig -notmatch 'runtime_name\s*=\s*"python"' -or $terraformConfig -notmatch 'runtime_version\s*=\s*"3\.12"') {
        throw 'The Flex Consumption Function App runtime must be Python 3.12.'
    }
    if ($allTerraform -match 'azurerm_linux_function_app\s*"') {
        throw 'The legacy Linux Consumption Function App resource is not allowed; use the Flex Consumption resource.'
    }

    $terraformVersionJson = & terraform version -json
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to query the Terraform CLI version.'
    }
    $terraformVersion = [version] ( $terraformVersionJson | ConvertFrom-Json ).terraform_version
    if ($terraformVersion -lt [version] '1.8.0') {
        throw "Terraform $terraformVersion is below the required minimum 1.8.0."
    }

    Invoke-CheckedCommand -Command 'terraform' -Arguments @('fmt', '-check', '-recursive')
    Invoke-CheckedCommand -Command 'terraform' -Arguments @('init', '-backend=false', '-input=false', '-lockfile=readonly')
    Invoke-CheckedCommand -Command 'terraform' -Arguments @('validate', '-no-color')
    Invoke-CheckedCommand -Command 'trivy' -Arguments @('config', '--exit-code', '1', '--severity', 'HIGH,CRITICAL', '--skip-dirs', '.terraform', '.')
}
finally {
    Pop-Location
}
