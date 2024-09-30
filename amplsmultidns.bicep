targetScope = 'resourceGroup'

param prefix string = 'cptdazampls'
param location string = resourceGroup().location
param principalId string // The object ID of the user or service principal


// Storage Account
resource sa1 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: '${prefix}1'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {}
}

resource sab1 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  name: 'default'
  parent: sa1
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: prefix
  parent: sab1
}

// Assign the "Storage Blob Data Contributor" role to the specified principal
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(sa1.id, 'Storage Blob Data Contributor', principalId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Role ID for "Storage Blob Data Contributor"
    principalId: principalId
    // scope: sa1.id
  }
}

// Enable Diagnostic Settings for Storage Account
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${prefix}sa1'
  scope: sab1
  properties: {
    workspaceId: law.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

resource sa2 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: '${prefix}2'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {}
}

// Create Hub VNet
resource hub1Vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: '${prefix}hub1'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: prefix
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

// Create Spoke VNet
resource spoke1Vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: '${prefix}spoke1'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.1.0.0/16']
    }
    subnets: [
      {
        name: prefix
        properties: {
          addressPrefix: '10.1.0.0/24'
        }
      }
    ]
  }
}

// Create Virtual Network Peering from Hub to Spoke
resource hub1ToSpoke1Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = {
  name: 'hub1ToSpoke1'
  parent: hub1Vnet
  properties: {
    remoteVirtualNetwork: {
      id: spoke1Vnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Create Virtual Network Peering from Spoke to Hub
resource spoke1ToHub1Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = {
  name: 'spoke1ToHub'
  parent: spoke1Vnet
  properties: {
    remoteVirtualNetwork: {
      id: hub1Vnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

// Create Log Analytics Workspace
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: prefix
  location: 'eastus'
  properties: {
    sku: {
      name: 'pergb2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    // The network access type for accessing Log Analytics ingestion.	Enabled, Disabled
    // When you disable public access for ingestion, 
    // no machine can send data to this component except those that are configured to send traffic through Azure Monitor Private Link.
    publicNetworkAccessForIngestion: 'Enabled'
    // The network access type for accessing Log Analytics query.	
    // When you disable public access for ingestion,
    // no machine can send data to this component except those that are configured to send traffic through Azure Monitor Private Link. Learn More
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource ampls 'microsoft.insights/privatelinkscopes@2021-07-01-preview' = {
  name: prefix
  location: 'global'
  properties: {
    accessModeSettings: {
      exclusions: []
      // Specifies the default access mode of ingestion through associated private endpoints in scope. 
      // If not specified default value is 'Open'. 
      // You can override this default setting for a specific private endpoint connection 
      // by adding an exclusion in the 'exclusions' array.	
      // Private Only – Allows the connected VNet to reach only Private Link resources. 
      // This is the most secure mode. Note: Only select 'Private Only' after adding all Azure Monitor resources to the AMPLS. 
      // Traffic to other resources will be blocked across networks, subscriptions, and tenants.
      // Open – Allows the connected VNet to reach both Private Link resources and resources not in the AMPLS. 
      // Traffic to Private Link resources is validated and sent through private endpoints, 
      // but data exfiltration can’t be prevented because traffic can reach resources outside of the AMPLS. 
      // The Open mode allows for a gradual onboarding process, combining Private Link access to some resources and public access to others.
      ingestionAccessMode: 'Open'
      // Specifies the default access mode of queries through associated private endpoints in scope. 
      // If not specified default value is 'Open'. 
      // You can override this default setting for a specific private endpoint connection by adding an exclusion in the 'exclusions' array.	
      queryAccessMode: 'PrivateOnly'
    }
  }
}

// Private Endpoints are network interfaces that connect you privately and securely to a service powered by Azure Private Link. 
// Private Endpoints use a private IP address from your Virtual Network, effectively bringing the service into your Virtual Network.
// They allow you to access Azure services (such as Azure Storage, Azure SQL Database, etc.) over a private IP address within your Virtual Network, without exposing the service to the public internet.
resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: prefix
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: prefix
        properties: {
          privateLinkServiceId: ampls.id
          groupIds: [
            'azuremonitor'
          ]
        }
      }
    ]
    manualPrivateLinkServiceConnections: []
    customNetworkInterfaceName: '${prefix}ampls'
    subnet: {
      id: '${hub1Vnet.id}/subnets/${prefix}'
    }
    ipConfigurations: []
    customDnsConfigs: []
  }
}

resource privateDnsZones_privatelink_monitor_azure_com 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.monitor.azure.com'
  location: 'global'
}

resource privateDnsZones_privatelink_oms_opinsights_azure_com 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.oms.opinsights.azure.com'
  location: 'global'
}

resource privateDnsZones_privatelink_ods_opinsights_azure_com 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.ods.opinsights.azure.com'
  location: 'global'
}

resource privateDnsZones_privatelink_agentsvc_azure_automation_net 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.agentsvc.azure-automation.net'
  location: 'global'
}

resource privateDnsZones_privatelink_blob_core_windows_net 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
}

// Private DNS Zone Groups link the private endpoint to one or more Private DNS Zones. 
// This ensures that DNS queries for the service's fully qualified domain name (FQDN) resolve to the private IP address of the private endpoint.

resource pePrivateDnsZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-06-01' = {
  name: prefix
  parent: pe
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-monitor-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_monitor_azure_com.id
        }
      }
      {
        name: 'privatelink-oms-opinsights-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_oms_opinsights_azure_com.id
        }
      }
      {
        name: 'privatelink-ods-opinsights-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_ods_opinsights_azure_com.id
        }
      }
      {
        name: 'privatelink-agentsvc-azure-automation-net'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_agentsvc_azure_automation_net.id
        }
      }
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_blob_core_windows_net.id
        }
      }
    ]
  }
}

resource plsResource 'microsoft.insights/privatelinkscopes/scopedresources@2021-07-01-preview' = {
  parent: ampls
  name: prefix
  properties: {
    linkedResourceId: law.id
  }
}


