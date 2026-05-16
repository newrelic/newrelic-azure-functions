###############################################################################
# VNet Flow Logs Forwarder - ARM Template Deployment Script (PowerShell)
###############################################################################
# This script deploys the VNet Flow Logs forwarder infrastructure using
# the ARM template and parameters file.
#
# Usage:
#   .\deploy.ps1 -ResourceGroupName <name> [-Location <location>]
#
# Example:
#   .\deploy.ps1 -ResourceGroupName bpavan-vnet-logs-arm -Location canadacentral
###############################################################################

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$false)]
    [string]$Location = "canadacentral"
)

# Function to print colored output
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check if Azure PowerShell module is installed
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Error "Azure PowerShell module is not installed. Please install it from: https://docs.microsoft.com/en-us/powershell/azure/install-az-ps"
    exit 1
}

# Check if logged in to Azure
$context = Get-AzContext
if (-not $context) {
    Write-Error "Not logged in to Azure. Please run 'Connect-AzAccount' first."
    exit 1
}

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplateFile = Join-Path $ScriptDir "azuredeploy-vnetflowlogsforwarder.json"
$ParametersFile = Join-Path $ScriptDir "azuredeploy-vnetflowlogsforwarder.parameters.json"

# Validate files exist
if (-not (Test-Path $TemplateFile)) {
    Write-Error "Template file not found: $TemplateFile"
    exit 1
}

if (-not (Test-Path $ParametersFile)) {
    Write-Error "Parameters file not found: $ParametersFile"
    exit 1
}

Write-Info "====================================================================="
Write-Info "VNet Flow Logs Forwarder - ARM Template Deployment"
Write-Info "====================================================================="
Write-Info "Resource Group: $ResourceGroupName"
Write-Info "Location: $Location"
Write-Info "Template: $TemplateFile"
Write-Info "Parameters: $ParametersFile"
Write-Info "====================================================================="
Write-Host ""

# Get current subscription
$Subscription = $context.Subscription.Name
Write-Info "Current Azure Subscription: $Subscription"
Write-Host ""

$response = Read-Host "Do you want to proceed with the deployment? (y/n)"
if ($response -notmatch "^[Yy]$") {
    Write-Warning "Deployment cancelled by user."
    exit 0
}

Write-Host ""
Write-Info "Step 1: Creating resource group (if it doesn't exist)..."
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if ($rg) {
    Write-Warning "Resource group '$ResourceGroupName' already exists. Using existing resource group."
} else {
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location | Out-Null
    Write-Success "Resource group created: $ResourceGroupName"
}

Write-Host ""
Write-Info "Step 2: Validating ARM template..."
$validation = Test-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $TemplateFile `
    -TemplateParameterFile $ParametersFile `
    -ErrorAction SilentlyContinue `
    -ErrorVariable validationErrors

if ($validation) {
    Write-Error "Template validation failed:"
    $validationErrors | ForEach-Object { Write-Host $_.Exception.Message -ForegroundColor Red }
    exit 1
} else {
    Write-Success "Template validation passed!"
}

Write-Host ""
Write-Info "Step 3: Running 'what-if' analysis..."
Write-Warning "This shows what resources will be created/modified..."
$whatIfResult = Get-AzResourceGroupDeploymentWhatIfResult `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $TemplateFile `
    -TemplateParameterFile $ParametersFile

Write-Host $whatIfResult

Write-Host ""
$response = Read-Host "Review the what-if output above. Continue with deployment? (y/n)"
if ($response -notmatch "^[Yy]$") {
    Write-Warning "Deployment cancelled by user."
    exit 0
}

Write-Host ""
Write-Info "Step 4: Deploying ARM template..."
Write-Warning "This may take 5-10 minutes..."
$DeploymentName = "vnetflowlogs-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

try {
    $deployment = New-AzResourceGroupDeployment `
        -Name $DeploymentName `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $TemplateFile `
        -TemplateParameterFile $ParametersFile `
        -ErrorAction Stop

    Write-Success "Deployment completed successfully!"

    # Extract outputs
    $FunctionAppName = $deployment.Outputs.functionAppName.Value
    $EventHubName = $deployment.Outputs.eventHubName.Value
    $StorageAccountName = $deployment.Outputs.storageAccountName.Value

    Write-Host ""
    Write-Info "====================================================================="
    Write-Info "Deployment Outputs"
    Write-Info "====================================================================="
    Write-Info "Function App Name: $FunctionAppName"
    Write-Info "Event Hub Name: $EventHubName"
    Write-Info "Storage Account Name: $StorageAccountName"
    Write-Info "====================================================================="

    Write-Host ""
    Write-Info "Step 5: Getting Function App Managed Identity..."
    $webapp = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName
    $PrincipalId = $webapp.Identity.PrincipalId

    Write-Success "Managed Identity Principal ID: $PrincipalId"

    Write-Host ""
    Write-Warning "====================================================================="
    Write-Warning "IMPORTANT: Post-Deployment Steps Required"
    Write-Warning "====================================================================="
    Write-Warning ""
    Write-Warning "You must grant the Function App read access to the source storage:"
    Write-Warning ""
    Write-Warning "Run these commands:"
    Write-Warning ""
    Write-Host "`$sourceStorage = Get-AzStorageAccount ``
    -ResourceGroupName bpavan-vnet-logs ``
    -Name bpavanvnetlogstorage

New-AzRoleAssignment ``
    -ObjectId $PrincipalId ``
    -RoleDefinitionName 'Storage Blob Data Reader' ``
    -Scope `$sourceStorage.Id" -ForegroundColor Yellow
    Write-Warning ""
    Write-Warning "====================================================================="

    Write-Host ""
    Write-Warning "====================================================================="
    Write-Warning "NEXT STEP: Deploy Function Code"
    Write-Warning "====================================================================="
    Write-Warning ""
    Write-Warning "The infrastructure is ready, but you need to deploy your function code."
    Write-Warning ""
    Write-Warning "Quick deployment:"
    Write-Warning ""
    Write-Host "  cd /Users/bpavan/repos/logint/nr/newrelic-azure-functions
  npm run package:logforwarder
  az functionapp deployment source config-zip ``
    --resource-group $ResourceGroupName ``
    --name $FunctionAppName ``
    --src LogForwarder.zip
  az functionapp restart --resource-group $ResourceGroupName --name $FunctionAppName" -ForegroundColor Yellow
    Write-Warning ""
    Write-Warning "For detailed instructions, see: vnet-flow-logs-spike/DEPLOY_CODE.md"
    Write-Warning "====================================================================="

    Write-Host ""
    Write-Success "Deployment script completed!"
    Write-Info "After deploying code, check the Azure Portal to monitor the function app."

} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    exit 1
}