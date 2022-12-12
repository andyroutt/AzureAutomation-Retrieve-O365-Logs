<#
.NOTES
              Version:          1.0
              Author:           Andy Routt
              Creation Date:    12/10/2022
              Purpose:          Azure Automation Runbook Script to Collect O365 Audit Logs and Write to an Azure Storage Blob
              License:          MIT
#> 

#####################
# USER VARIABLES
#####################

# Tenant Variables
$tenantdomain = "[yourdomain].onmicrosoft.com"              # Tenant Domain
$TenantGUID = "[tenant ID]"                                 # Tenant ID
$Subscription = "[subscription ID]"                         # Azure Subscription ID

# Runbook Variables
$identitylName = "O365AuditLogsApp-Secret"                  # Azure Automation Account Credential Name
$AppClientID = "[app registration ID]"                      # Applicatioin ID for Office Management API Registration

# Storage Account Variables
$resourceGroupName = "[resource group of storage account]"  # Storage Account Resource Group
$storageAccountName = "[storage account name]"              # Storage Account Name
$containerName = "[blob container name]"                    # Storage Account Container Name

# Enable/Disable Debug Logging
# $GLOBAL:DebugPreference="Continue"                          # Uncomment to Enable Debug

Write-Debug "Debugging Enabled" 5>&1
Write-Debug "" 5>&1ß


#####################
# SCRIPT VARIABLES
#####################

# OMI Variables
$APIResource = "https://manage.office.com"
$loginURL = "https://login.microsoftonline.com/"
$BaseURI = "$APIResource/api/v1.0/$tenantGUID/activity/feed/subscriptions"
$Subscriptions = @('Audit.AzureActiveDirectory','Audit.Exchange','Audit.SharePoint','Audit.General','DLP.All')
$Date = Get-date
$blobFolder = $Date.ToString('yyyy-MM-dd')
$fileDate = $Date.ToString('yyyy-MM-dd_hh-mm-ss') + "Z"

# SAS Variables
$startTime     = Get-Date
$expiryTime    = $startTime.AddDays(1)
$permissions   = "rwl"
$protocol      = "HttpsOnly"

Write-Output "Date: $Date"
Write-Output ""

#####################
# OAUTH TOKEN
#####################

# Retrieved Managed Identity Credential
$myCredential = Get-AutomationPSCredential -Name $identitylName
$securePassword = $myCredential.Password
$ClientSecretValue = $myCredential.GetNetworkCredential().Password

# Create OAUTH Token to access OMI Subscriptions Containing O365 Logs
Write-Output "Obtaining OAUTH Token ..."
$body = @{grant_type="client_credentials";resource=$APIResource;client_id=$AppClientID;client_secret=$ClientSecretValue}
try {
    $oauth = Invoke-RestMethod -Method Post -Uri "$loginURL/$tenantdomain/oauth2/token?api-version=1.0" -Body $body -ErrorAction Stop
    $OfficeToken = @{'Authorization'="$($oauth.token_type) $($oauth.access_token)"}
    Write-Output "SUCCESS"
    Write-Output ""
} catch {
    Write-Output "FAILED"
	Write-Output ""
    Write-Output $error[0]
    exit
}

# Debug
$bearer_token = $OfficeToken.Authorization
Write-Debug  "Bearer Token:" 5>&1
Write-Debug  "" 5>&1
Write-Debug  "$bearer_token" 5>&1
Write-Debug  "" 5>&1

$CheckSub = Invoke-WebRequest -Headers $OfficeToken -Uri "$BaseURI/list" -UseBasicParsing
Write-Debug  "Subscriptions: ..." 5>&1
Write-Debug  "" 5>&1
Write-Debug  $CheckSub 3>&1
Write-Debug  "" 5>&1

#####################
# SAS TOKEN
#####################

# Create Context to Hold Azure Authentication Session
Write-Output "Connectiing to Azure ..."
try {
    Disable-AzContextAutosave -Scope Process | Out-Null
    $AzureContext = (Connect-AzAccount -Identity).context
    $AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext
	Write-Output "SUCCESS"
	Write-Output ""
} catch {
    Write-Output "FAILED"
	Write-Output ""
    Write-Error -Message $_.Exception
    throw $_.Exception
    exit
}

# Create SAS Token for Writing to Azure Storage Blob
Write-Output "Obtaining SAS Token ..."
try {

    # Create Azure Context to Access Azure Storage
    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
         
    # Generate SAS Token for Blob Storage Container
    $sas_token = New-AzStorageContainerSASToken `
        -Context $ctx `
        -Name $containerName `
        -StartTime $startTime `
        -ExpiryTime $expiryTime `
        -Permission $permissions `
        -Protocol $protocol
    Write-Output "SUCCESS"
    Write-Output ""

} catch {
    Write-Output "FAILED"
    Write-Output ""
    Write-Error -Message $_.Exception
    throw $_.Exception
    exit
}

# Debug
Write-Debug  "SAS Token:" 5>&1
Write-Debug  "" 5>&1
Write-Debug  "$sas_token" 5>&1
Write-Debug  "" 5>&1

$existing_blobs = Get-AzStorageBlob -Container $containerName -Context $ctx | ft -property name, LastModified | Out-String
Write-Debug "Existing Blobs: ..." 5>&1
Write-Debug "" 5>&1
Write-Debug "$existing_blobs" 5>&1
Write-Debug "" 5>&1


#####################
# Functions
#####################

# Function -- Retrieve and Format Content URIs for Subscription
function buildLog($BaseURI, $Subscription, $tenantGUID, $OfficeToken){

    # Retrieve Content Page Containing URIs
    try {
        $Log = Invoke-WebRequest -Method GET -Headers $OfficeToken -Uri "$BaseURI/content?contentType=$Subscription&PublisherIdentifier=$TenantGUID" -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Output "Invoke-WebRequest ... FAILED"
        Write-Output ""
        Write-Output $error[0]
        return
    }

    # Check for Additional Content Pages
    if ($Log.Headers.NextPageUri) {
        $NextContentPage = $true
        $NextContentPageURI = $Log.Headers.NextPageUri

        while ($NextContentPage -ne $false){

            $ThisContentPage = Invoke-WebRequest -Headers $OfficeToken -Uri $NextContentPageURI -UseBasicParsing
            $TotalContentPages += $ThisContentPage

            if ($ThisContentPage.Headers.NextPageUri){
                $NextContentPage = $true    
            } Else {
                $NextContentPage = $false
            }
            $NextContentPageURI = $ThisContentPage.Headers.NextPageUri
        }
    }
    $TotalContentPages += $Log
    return $TotalContentPages
}

# Function -- Format URIs and Export Logs to Azure Storage Blob
function outputToFile($TotalContentPages, $JSONfilename, $Officetoken, $blobFolder, $containerName, $ctx){

    # Retrieve URIs from Content Pages
    if($TotalContentPages.content.length -gt 2){
        $uris = @()
        $pages = $TotalContentPages.content.split(",")
        
        foreach($page in $pages){
            if($page -match "contenturi"){
                $uri = $page.split(":")[2] -replace """"
                $uri = "https:$uri"
                $uris += $uri
            }
        }

        # Fetch and Write All URIs
        foreach($uri in $uris){
            try {

                # Debug
                Write-Debug "Fetching ... $uri" 5>&1
                Write-Debug  "" 5>&1

                # Retrieve Log Data from Content URI
                $Logdata += Invoke-RestMethod -Uri $uri -Headers $Officetoken -Method Get
                
                # Write Log Data to Azure Storage Blob Temp (Out-File Automatically Uses $env:temp)
                # WARNING --> There is a 1GB maximum file size of Azure Blob temporary sandbox storage
                # https://learn.microsoft.com/en-us/azure/automation/automation-runbook-execution#temporary-storage-in-a-sandbox 
                $Logdata | ConvertTo-Json -Depth 100 | Out-File -Encoding UTF8 -FilePath $JSONfilename

            } catch {
                Write-Output "ERROR Fetching ... $uri"
                Write-Output $error[0]
                Write-Output ""
                return
            }      
        }

        # Store Blob Data by Date
        $blobFileName = $blobFolder + "/" + $JSONfilename

        # Retrieve Log Data from Azure Storage Blob Temp and Write to Azure Storage Blob Container
        Write-Debug "Writing blob data to ... $blobFileName" 5>&1
        Write-Debug  "" 5>&1
        try {
            Set-AzStorageBlobContent -File $JSONfilename -Blob $blobFileName -Container $containerName -Context $ctx | Out-null
            Write-Output  "SAVED ... $blobFileName"

        } catch {
            Write-Output "ERROR Writing ... $blobFileName"
            Write-Error -Message $_.Exception
            throw $_.Exception
            Write-Output ""
        }

    } else {

        # Debug
        Write-Debug  "" 5>&1
        Write-Debug  "Moving to Next Subscription ..." 5>&1
        Write-Debug  "" 5>&1
    }
}

#####################
# Export Logs
#####################

# Collect and Export Log Data by Subscription
foreach($Subscription in $Subscriptions){
    
    # Debug
    Write-Debug "" 5>&1
    Write-Debug "Collecting log data from ..." 5>&1
    Write-Debug "" 5>&1
    Write-Debug "$Subscription" 5>&1
    Write-Debug "" 5>&1

    $logs = buildLog $BaseURI $Subscription $TenantGUID $OfficeToken
    $JSONfilename = ($Subscription + "_" + $fileDate + ".json")

    # DEBUG
    Write-Debug "----- Content Pages -----" 5>&1
    Write-Debug "$logs" 5>&1
    Write-Debug "----- Content Pages -----" 5>&1
    Write-Debug "" 5>&1

    # Write JSON Log Data to Azure Blob Storage
    outputToFile $logs $JSONfilename $OfficeToken $blobFolder $containerName $ctx

}
