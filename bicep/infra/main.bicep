@description('The name of the connected k8s to have KV extension.')
param ArcK8sName string
@description('resource group of kubernetes cluster')
param ClusterResourceGroup string

@description('New resource group name to create sample resources')
param SampleResourceGroup string
@description('location of SampleResourceGroup')
param SampleResourceLocation string

@description('The objid of service principal to grant keyvault access')
param objid string

@description('The name of the key vault to be created.')
param VaultName string

@description('The name of the Azure Container Registry')
param acrName string

@description('The name of the ACR token')
param tokenName string

targetScope = 'subscription'

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: SampleResourceGroup
  location: SampleResourceLocation
}

module extension 'clusterextension.bicep' = {
  name: 'extension'
  scope: resourceGroup(ClusterResourceGroup)
  params: {
    ArcK8sName: ArcK8sName
  }
}
module resources 'resource.bicep' = {
  name: 'createresources'
  scope: rg
  params: {
    SampleResourceLocation: SampleResourceLocation
    VaultName: VaultName
    objid: objid
    acrName: acrName
    tokenName: tokenName
  }
}
