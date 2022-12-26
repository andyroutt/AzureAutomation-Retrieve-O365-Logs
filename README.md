# AzureAutomation-Retrieve-O365-Logs

Azure Automation script to retrieve Office 365 Audit Logs. This script was adapted from the [Compliance-API Script](https://github.com/walidelmorsy/Microsoft-365-Compliance-API) to include the ability to execute as a Runbook and write the output to an Azure Storage Blob.


### Prerequisites

- Azure AD App Registration with Office Management API Permissions
- Azure Automation Account
- Azure Storage Account

### Azure App Registration Setup (Office Management API)

1. Create an Azure AD App Registration &rarr; [Register your application in Azure AD](https://learn.microsoft.com/en-us/office/office-365-management-api/get-started-with-office-365-management-apis#register-your-application-in-azure-ad)

	- Follow the instructions to register a new Azure AD application.

2. Create an App Registration Key &rarr; [Generate a new key for your application](https://learn.microsoft.com/en-us/office/office-365-management-api/get-started-with-office-365-management-apis#generate-a-new-key-for-your-application)

	- Follow the instructions to create a new client secret to access the app registration.

3. Assign Office Management API Permissions &rarr; [Specify the permissions your app requires to access the Office 365 Management APIs](https://learn.microsoft.com/en-us/office/office-365-management-api/get-started-with-office-365-management-apis#specify-the-permissions-your-app-requires-to-access-the-office-365-management-apis)

	- Follow the instructions to grant Office Management API permissions to the App Registration.

4. Grant Admin Consent for Office Management API Permissions &rarr; [Get Office 365 tenant admin consent](https://learn.microsoft.com/en-us/office/office-365-management-api/get-started-with-office-365-management-apis#get-office-365-tenant-admin-consent)

	- Follow the instructions to approve Office Management API permissions for the App Registration.

5. Generate an Access Token &rarr; [Request an access token by using client credentials](https://learn.microsoft.com/en-us/office/office-365-management-api/get-started-with-office-365-management-apis#request-an-access-token-by-using-client-credentials)

	- Follow the instructions to generate and access token to access and retrieve Office 365 log subscriptions. 

	<ins>BASH/ZSH Command Line Steps</ins>

	```
	% tenant="[your domain]"
	% tenantid="[your tenant ID]"
	% clientid="[your app registration ID]"
	% clientsecret="[app registration client secret]"
	% resource="https://manage.office.com"
	
	% token=`curl -s -X POST -H 'Content-Type: application/x-www-form-urlencoded' \
	https://login.microsoftonline.com/$tenant/oauth2/token \
	-d 'grant_type=client_credentials' \
	-d client_id=$clientid \
	-d client_secret=$clientsecret \
	-d resource=$resource | jq -r '.access_token'`
	```

	<ins>PowerShell Steps</ins>

	```
	PS> $tenant="[your domain]"
	PS> $tenantid="[your tenant ID]"
	PS> $clientid="[your app registration ID]"
	PS> $clientsecret="[app registration client secret]"
	PS> $resource="https://manage.office.com" 
	PS> $body=@{grant_type="client_credentials";resource=$resource;client_id=$clientid;client_secret=$clientsecret} 
	PS> $oauth=Invoke-RestMethod -Method Post -Uri https://login.microsoftonline.com/$tenant/oauth2/token?api-version=1.0 -Body $body 
	PS> $headerParams=@{'Authorization'="$($oauth.token_type) $($oauth.access_token)"}
	```

6. Start the Office Management API Subscriptions &rarr; [Start a subscription](https://learn.microsoft.com/en-us/office/office-365-management-api/office-365-management-activity-api-reference?source=recommendations#start-a-subscription)

	- Follow the instructions to start a subscription for each content type.
	<br>

	|        Content Type        |                  Description                  |
	|----------------------------|-----------------------------------------------|
	| Audit.AzureActiveDirectory | Azure Active Directory Logs (Office 365 Only) |
	| Audit.Exchange             | Exchange Online Logs                          |
	| Audit.SharePoint           | SharePoint Online Logs                        |
	| Audit.General              | Other Logs                                    |
	| DLP.All                    | DLP Logs                                      |


	<ins>BASH/ZSH Command Line Steps</ins>

	Start Subscriptions

	```
	% curl -s -d -G -X POST -H "Authorization: Bearer $token" https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=Audit.AzureActiveDirectory&PublisherIdentifier=$tenantid
	% curl -s -d -G -X POST -H "Authorization: Bearer $token" https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=Audit.General&PublisherIdentifier=$tenantid
	% curl -s -d -G -X POST -H "Authorization: Bearer $token" https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=Audit.Exchange&PublisherIdentifier=$tenantid
	% curl -s -d -G -X POST -H "Authorization: Bearer $token" https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=Audit.SharePoint&PublisherIdentifier=$tenantid
	% curl -s -d -G -X POST -H "Authorization: Bearer $token" https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=DLP.All&PublisherIdentifier=$tenantid
	```
	<ins>PowerShell Steps</ins>

	Start Subscriptions

	```
	PS> Invoke-WebRequest -Method POST -Headers $headerParams -Uri "https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=Audit.AzureActiveDirectory&PublisherIdentifier=$tenantid"
	PS> Invoke-WebRequest -Method POST -Headers $headerParams -Uri "https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=Audit.General&PublisherIdentifier=$tenantid"
	PS> Invoke-WebRequest -Method POST -Headers $headerParams -Uri "https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=Audit.Exchange&PublisherIdentifier=$tenantid"
	PS> Invoke-WebRequest -Method POST -Headers $headerParams -Uri "https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=Audit.SharePoint&PublisherIdentifier=$tenantid"
	PS> Invoke-WebRequest -Method POST -Headers $headerParams -Uri "https://manage.office.com/api/v1.0/$tenant/activity/feed/subscriptions/start?contentType=DLP.All&PublisherIdentifier=$tenantid"
	```

### Azure Blob Setup

1. Create an Azure Storage Account &rarr; [Create a storage account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal#create-a-storage-account-1) 
	- Follow the instructions to create a new storage account.

2. Create a Blob Container &rarr; [Create a container](https://learn.microsoft.com/en-us/azure/storage/blobs/blob-containers-portal#create-a-container)
	- Follow the instructions to create a new blob container within the storage account.

### Azure Automation Account Setup

1. Create an Azure Automation Account &rarr; [Create Automation account](https://learn.microsoft.com/en-us/azure/automation/quickstarts/create-azure-automation-account-portal#create-automation-account)

	- Follow the instructions to create a new automation account.

2. Configure Managed Identity &rarr; [Enable system-assigned managed identity](https://learn.microsoft.com/en-us/azure/automation/quickstarts/enable-managed-identity#enable-system-assigned-managed-identity)

	- Follow the instructions to add a managed identity to the Azure automation account.

		_Account Settings &rarr; Identity &rarr; System Assigned_

>		- Status: On
>		- Permissions: Storage Blob Data Owner
>		- Resource: [storage account name]


3. Add Client Secret to Access App Registration &rarr; [Create a new credential asset](https://learn.microsoft.com/en-us/azure/automation/shared-resources/credentials?tabs=azure-powershell#create-a-new-credential-asset)

	- Follow the instructions to add a client secret to the Azure automation account.

		_Shared Resources &rarr; Credentials &rarr; Add a credential_

>		- Name: O365AuditLogsApp-Secret
>		- Password: [app registration client secret]

4. Create Runbook  &rarr; [Create PowerShell runbook](https://learn.microsoft.com/en-us/azure/automation/learn/powershell-runbook-managed-identity#create-powershell-runbook)

	- Follow the instructions to add a runbook to the Azure automation account.

		_Process Automation &rarr; Runbooks &rarr; Create a runbook &rarr; Edit &rarr; [Paste Script] &rarr; Save &rarr; Publish_

>		- Name: Collect_O365_Logs
>		- Type: Powershell
>		- Version: 5.1

4. Schedule Runbook &rarr; [Create a schedule](https://learn.microsoft.com/en-us/azure/automation/shared-resources/schedules#create-a-schedule)

	- Follow the instructions to create a schedule for the runbook within the Azure automation account.

		_Shared Resources &rarr; Schedules &rarr; Add a schedule_

>		- Name: Collect O365 Daily
>		- Recurrence: Every 1 Day


5. Link Schedule to Runbook &rarr; [Link a schedule to a runbook](https://learn.microsoft.com/en-us/azure/automation/shared-resources/schedules#link-a-schedule-to-a-runbook)

	- Follow the instructions to link a schedule to a runbook within the Azure automation account.

		_Process Automation &rarr; Runbooks &rarr; Collect_O365_Logs
		Link to schedule &rarr; Link a schedule to your runbook &rarr; Collect O365 Logs Daily_

### Disclaimer

This is a proof of concept script meant for testing purposes only. Use at your own risk.


