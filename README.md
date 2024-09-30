# Azure Sentinel

## Azure Sentinel and Private Endpoint

Based on 
- https://techcommunity.microsoft.com/t5/fasttrack-for-azure/how-azure-monitor-s-implementation-of-private-link-differs-from/ba-p/3608938


### Deploy AMPLS

Most of the configuration is done via the Portal.
Afterwards we did move some of the settings into the Bicep file ampls.bicep.
So we can modify the different AMPLS settings via the Bicep file.

~~~powershell
$prefix="cptdazsentinel"
az deployment group create --name $prefix --resource-group $prefix --template-file ampls.bicep # Works
~~~

### Verify DNS lookup on Azure VM:

We will lookup api.privatelink.monitor.azure.com insread of api.loganalytics.io.
Thats because of the CNAME change and the more relevant FQDN is the api.privatelink.monitor.azure.com. one.

~~~powershell
nslookup api.loganalytics.io
Server:  UnKnown
Address:  168.63.129.16

Non-authoritative answer:
Name:    api.privatelink.monitor.azure.com
Address:  10.0.0.13
Aliases:  api.loganalytics.io
          api.monitor.azure.com

nslookup api.privatelink.monitor.azure.com
Server:  UnKnown
Address:  168.63.129.16

Non-authoritative answer:
Name:    api.privatelink.monitor.azure.com
Address:  10.0.0.13
~~~

Like we can see most of the magic happens on api.privatelink.monitor.azure.com. Thats where AMPLS makes a decision about which IP to use, private or public.

### Verify DNS lookup on my local pc:

~~~powershell
nslookup api.loganalytics.io
Server:  fritz.box
Address:  fd00::3a10:d5ff:fe07:3c7b

Non-authoritative answer:
Name:    commoninfra-prod-dewc-0-ingress-draft.germanywestcentral.cloudapp.azure.com
Address:  20.218.184.197
Aliases:  api.loganalytics.io
          api.monitor.azure.com
          api.privatelink.monitor.azure.com
          draftprodglobal.trafficmanager.net

nslookup api.privatelink.monitor.azure.com
Server:  fritz.box
Address:  fd00::3a10:d5ff:fe07:3c7b

Non-authoritative answer:
Name:    commoninfra-prod-dewc-0-ingress-draft.germanywestcentral.cloudapp.azure.com
Address:  20.218.184.197
Aliases:  api.privatelink.monitor.azure.com
          draftprodglobal.trafficmanager.net
~~~

Here we can see that the api.privatelink.monitor.azure.com is resolved to the public IP address

####  Test 

Connect to VM via Bastion and RDP to test via AMPLS.

~~~powershell
# get id of vm via azure cli
$prefix="cptdazsentinel"
$vmid=az vm show -g $prefix -n $prefix --query id -o tsv
# rdp into vm via bastion
az network bastion rdp -n $prefix -g $prefix --target-resource-id $vmid
~~~

### Send Request to Storage Account

~~~powershell
# send request to storage account to create some logs on law
curl -v https://$prefix.blob.core.windows.net/$prefix/test.txt # 200 ok
~~~

### Retrieve logs from Logs from Log Analytics Workspace assigned to the AMPLS

Retrieve logs from log analytics workspace assigend to the AMPLS

~~~powershell
$prefix="cptdazsentinel"
# retrieve logs from log analytics workspace via corresponding rest api
$workspaceid=az monitor log-analytics workspace show -g $prefix -n $prefix --query customerId -o tsv
# get logs
az monitor log-analytics query -w $workspaceid --analytics-query "StorageBlobLogs | where TimeGenerated > ago(6d)| where ObjectKey == '/cptdazsentinel/cptdazsentinel/test.txt'| where OperationName == 'GetBlob'| where AuthenticationType == 'Anonymous'" --debug
~~~

### Retrieve logs from Logs from Log Analytics Workspace not assigned to the AMPLS

~~~powershell
# retrieve logs from log analytics workspace via corresponding rest api
$workspaceidext=az monitor log-analytics workspace show -g cptdazstorage -n cptdazstorage --query customerId -o tsv
# get logs
az monitor log-analytics query -w $workspaceidext --analytics-query "StorageBlobLogs | where TimeGenerated > ago(6d)| where CorrelationId == '8a5fb302-301e-0011-735c-91632d000000'" --debug
~~~

StorageBlobLogs 
| where CorrelationId == "8a5fb302-301e-0011-735c-91632d000000"

Log query request is send to https://api.loganalytics.io:443

### Block query request to Log Analytics Workspace

~~~powershell
# block query request to log analytics workspace
az network private-endpoint-connection update --name $prefix --resource-group $prefix --status Rejected
~~~

### Show current status

~~~powershell
az resource show -g $prefix -n $prefix --api-version "2021-07-01-preview" --resource-type Microsoft.Insights/privateLinkScopes --query properties.accessModeSettings
~~~

~~~json
{
  "exclusions": [],
  "ingestionAccessMode": "Open",
  "queryAccessMode": "Open"
}
~~~

~~~powershell
az resource show -g $prefix -n $prefix --api-version "2023-09-01" --resource-type Microsoft.OperationalInsights/workspaces --query "properties.{publicNetworkAccessForIngestion:publicNetworkAccessForIngestion,publicNetworkAccessForQuery:publicNetworkAccessForQuery}"
~~~

~~~json
{
  "publicNetworkAccessForIngestion": "Enabled",
  "publicNetworkAccessForQuery": "Enabled"
}
~~~

### Test 1: AMPLS with PrivateOnly Query Access Mode

|Test# | Resource                                   | Value      |
|------| ------------------------------------------ | ---------- |
|1     | privatelinkscopes.queryAccessMode          | PrivateOnly|
|1     | privatelinkscopes.ingestionAccessMode      | Open       |
|1     | workspaces.publicNetworkAccessForIngestion | Enabled    |
|1     | workspaces.publicNetworkAccessForQuery     | Enabled    |

|Test# | Client   | FQDN                             | IP             | LAW          | Result |
|------| --------| --------------------------------- | -------------- |--------------|------------------------ |
|1     | LocalPC | api.privatelink.monitor.azure.com | 20.218.184.197 | AMPLS-Linked | 200 OK                  |
|1     | LocalPC | api.privatelink.monitor.azure.com | 20.218.184.197 | None-AMPLS   | 200 OK                  |
|1     | LocalPC | api.privatelink.monitor.azure.com | 10.0.0.13      | AMPLS-Linked | 200 OK                  |
|1     | AzVM    | api.privatelink.monitor.azure.com | 10.0.0.13      | None-AMPLS   | InsufficientAccessError |

### Test 2: AMPLS with PrivateOnly Query Access Mode and workspace query access disabled

|Test# | Resource                                   | Value      |
|------| ------------------------------------------ | ---------- |
|2     | privatelinkscopes.queryAccessMode          | PrivateOnly|
|2     | privatelinkscopes.ingestionAccessMode      | Open       |
|2     | workspaces.publicNetworkAccessForIngestion | Enabled    |
|2     | workspaces.publicNetworkAccessForQuery     | Disabled    |

|Test# | Client   | FQDN                             | IP             | LAW          | Result |
|------| --------| --------------------------------- | -------------- |--------------|------------------------ |
|2     | LocalPC | api.privatelink.monitor.azure.com | 20.218.184.197 | AMPLS-Linked | InsufficientAccessError |
|2     | LocalPC | api.privatelink.monitor.azure.com | 20.218.184.197 | None-AMPLS   | 200 OK                  |
|2     | LocalPC | api.privatelink.monitor.azure.com | 10.0.0.13      | AMPLS-Linked | 200 OK                  |
|2     | AzVM    | api.privatelink.monitor.azure.com | 10.0.0.13      | None-AMPLS   | InsufficientAccessError |

Test via Azure Portal from my local pc does not show an error message, instead I do get the Message: "No results found from the last 7 days  
Try  selecting another time range".

### DNS Host file

We will use the windows DNS Hostfile to bypass the private DNS name resolution for the api.privatelink.monitor.azure.com.

~~~powershell
# you need to be on the Azure VM
# Make sure to run the following command as Administrator
note C:\Windows\System32\drivers\etc api.monitor.azure.com 
# add the following line to the file
20.218.184.197 api.privatelink.monitor.azure.com
20.218.184.197 api.loganalytics.io
# nslookup will not work on host file changes, so please use ping
ping api.loganalytics.io

Pinging api.loganalytics.io [20.218.184.197] with 32 bytes of data:
Request timed out.

# query from external law
az monitor log-analytics query -w $workspaceidext --analytics-query "StorageBlobLogs | where TimeGenerated > ago(6d)| where CorrelationId == '8a5fb302-301e-0011-735c-91632d000000'" # 200 OK
~~~

To overcome this you will need to make use of Azure Network Security Group (NSG) to block the traffic to the public IP address of the api.loganalytics.io.

### Azure Monitor and Data Collection Endpoint

https://cptdazsentinel-yjxe.eastus-1.handler.control.monitor.azure.com

## AMPLS and the DNS overwrite issue

~~~powershell
az provider register --namespace Microsoft.Network
az provider show --namespace Microsoft.Network --query "registrationState"
$currentUserObjectId=az ad signed-in-user show --query id -o tsv
$location="germanywestcentral"
$prefix="cptdazampls"
az group create --name $prefix --location $location
az deployment group create --name $prefix --resource-group $prefix --template-file amplsmultidns.bicep --parameters principalId=$currentUserObjectId
az group delete -n $prefix --yes --no-wait
$sa1ResourceId=az resource show -n ${prefix}1 -g $prefix --resource-type "Microsoft.Storage/storageAccounts" --query id -o tsv

az monitor diagnostic-settings categories -h list --resource $sa1ResourceId

# list private dns zones records for the storage account
az network private-dns record-set a list -g $prefix --zone-name privatelink.blob.core.windows.net --query "[].fqdn" # scadvisorcontentpl.privatelink.blob.core.windows.net

~~~

https://app.atroposs.com/#/start



  "cptdazampls1.privatelink.blob.core.windows.net.",
  "scadvisorcontentpl.privatelink.blob.core.windows.net."

## Misc

### github

~~~ bash
gh auth login
gh repo create $prefix --public
git init
git remote remove origin
git remote add origin https://github.com/cpinotossi/$prefix.git
git remote -v
git status
git add .gitignore
git add .
git commit -m"host file case"
git push origin main
~~~