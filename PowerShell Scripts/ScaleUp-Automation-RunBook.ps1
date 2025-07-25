# This sample PowerShell runbook calls the Power BI API and ARM REST API to programmatically scale a capacity resource
# This script can be called in Azure automation and triggered by Azure alert 
# This is only a basic script that contains samples for reading the WebhookData generated by the alert and scaling up the capacity
# See also
# https://docs.microsoft.com/power-bi/developer/embedded/monitor-power-bi-embedded-reference
# https://docs.microsoft.com/azure/automation/automation-create-standalone-account
# https://docs.microsoft.com/azure/automation/create-run-as-account
# https://docs.microsoft.com/azure/azure-monitor/alerts/alerts-overview


[OutputType("PSAzureOperationResponse")]

param
(
    [Parameter (Mandatory=$false)]
    [object] $WebhookData
)

$ErrorActionPreference = "stop"

if ($WebhookData)
{
    # Allow testing with WebhookData
    if (-NOT $WebhookData.RequestBody)
    {
           $WebhookData = (ConvertFrom-Json -InputObject $WebhookData)           
    }

    # Get the data object from WebhookData
    $WebhookBody = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)

    # Get the info needed to identify the PowerBIDedicated resource (depends on the payload schema)
    $schemaId = $WebhookBody.schemaId
    Write-Verbose "schemaId: $schemaId" -Verbose
    if ($schemaId -eq "AzureMonitorMetricAlert") {
        
        # This is the near-real-time metric alert schema
        $AlertContext = [object] ($WebhookBody.data).context
        $ResourceName = $AlertContext.resourceName
        $status = ($WebhookBody.data).status
    }

    Write-Verbose "status: $status" -Verbose
    if ($status -eq "Activated")
    {
        $ResourceType = $AlertContext.resourceType
        $ResourceGroupName = $AlertContext.resourceGroupName
        $SubId = $AlertContext.subscriptionId
        Write-Verbose "resourceType: $ResourceType" -Verbose
        Write-Verbose "resourceName: $ResourceName" -Verbose
        Write-Verbose "resourceGroupName: $ResourceGroupName" -Verbose
        Write-Verbose "subscriptionId: $SubId" -Verbose

        # Use this only if this is a resource management PowerBiDedicated
         Write-Verbose "resourceType: $ResourceType" -Verbose
        if ($ResourceType -eq "Microsoft.PowerBIDedicated/capacities")
        {
            # Authenticate to Azure by using the service principal and certificate. Then, set the subscription.
            $ConnectionAssetName = "AzureRunAsConnection"
            Write-Verbose "Get connection asset: $ConnectionAssetName" -Verbose
            $Conn = Get-AutomationConnection -Name $ConnectionAssetName
            if ($null -eq $Conn)
            {
               throw "Could not retrieve connection asset: $ConnectionAssetName. Check that this asset exists in the Automation account."
            }
            Write-Verbose "Authenticating to Azure with service principal." -Verbose

            Connect-AzureRmAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint | Write-Verbose
            Write-Verbose "Setting subscription to work against: $SubId" -Verbose
            Set-AzureRmContext -SubscriptionId $SubId -ErrorAction Stop | Write-Verbose

            $resourceInfo = Get-AzureRmPowerBIEmbeddedCapacity -ResourceGroupName $ResourceGroupName -Name $ResourceName
            Write-Verbose "ResourceSku: $resourceInfo.Sku" -Verbose
            
            if ($resourceInfo.Sku -eq "A1")
            {
              $scaleSku = "A2"
            }

            Update-AzureRmPowerBIEmbeddedCapacity -ResourceGroupName $ResourceGroupName -Name $ResourceName -Sku $scaleSku
        }
        else {
            # ResourceType isn't supported
            Write-Error "$ResourceType is not a supported resource type for this runbook."
        }
    }
    else {
        # The alert status was not 'Activated', so no action taken
        Write-Verbose ("No action taken. Alert status: " + $status) -Verbose
    }
}
else {
    # Error
    Write-Error "This runbook is meant to be started from an Azure alert webhook only."
}
