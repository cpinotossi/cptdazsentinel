targetScope = 'resourceGroup'

param prefix string = 'cptdazsentinel'
// param workspaces_cptdazsentinel_externalid string = '/subscriptions/f474dec9-5bab-47a3-b4d3-e641dac87ddb/resourceGroups/cptdazsentinel/providers/microsoft.operationalinsights/workspaces/cptdazsentinel'

// resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
//   name: prefix
// }

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
      queryAccessMode: 'Open'
    }
  }
}

// resource symbolicname 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = {
//   name: 'string'
//   location: 'string'
//   properties: {
//     accessModeSettings: {
//       exclusions: [
//         {
//           ingestionAccessMode: 'string'
//           privateEndpointConnectionName: 'string'
//           queryAccessMode: 'string'
//         }
//       ]
//       ingestionAccessMode: 'string'
//       queryAccessMode: 'string'
//     }
//   }
// }

// resource plsConnection 'microsoft.insights/privatelinkscopes/privateendpointconnections@2021-07-01-preview' existing = {
//   parent: ampls
//   name: prefix
// }

// resource plsConnection 'microsoft.insights/privatelinkscopes/privateendpointconnections@2021-07-01-preview' = {
//   parent: ampls
//   name: prefix
//   properties: {
//     privateEndpoint: {}
//     privateLinkServiceConnectionState: {
//       status: 'Approved'
//     }
//   }
// }

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: prefix
}

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: prefix
  location: 'eastus'
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
      id: '${vnet.id}/subnets/${prefix}'
    }
    ipConfigurations: []
    customDnsConfigs: []
  }
}

resource privateDnsZones_privatelink_monitor_azure_com 'Microsoft.Network/privateDnsZones@2020-06-01'  existing = {
  name: 'privatelink.monitor.azure.com'
}

resource privateDnsZones_privatelink_oms_opinsights_azure_com_externalid 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.oms.opinsights.azure.com'
}

resource privateDnsZones_privatelink_ods_opinsights_azure_com_externalid 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.ods.opinsights.azure.com'
}

resource privateDnsZones_privatelink_agentsvc_azure_automation_net_externalid 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.agentsvc.azure-automation.net'
}

resource privateDnsZones_privatelink_blob_core_windows_net_externalid 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.blob.core.windows.net'
}

resource privateEndpoints_cptdazsentinel_name_default 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2020-06-01' = {
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
          privateDnsZoneId: privateDnsZones_privatelink_oms_opinsights_azure_com_externalid.id
        }
      }
      {
        name: 'privatelink-ods-opinsights-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_ods_opinsights_azure_com_externalid.id
        }
      }
      {
        name: 'privatelink-agentsvc-azure-automation-net'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_agentsvc_azure_automation_net_externalid.id
        }
      }
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZones_privatelink_blob_core_windows_net_externalid.id
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


