

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

resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: SampleResourceLocation
  sku: {
    name: 'Standard'
  }
}

resource scope 'Microsoft.ContainerRegistry/registries/scopeMaps@2023-01-01-preview' existing = {
  name: '_repositories_pull'
  parent: acr
}

resource token 'Microsoft.ContainerRegistry/registries/tokens@2023-01-01-preview' = {
  name: tokenName
  parent: acr
  properties: {
    scopeMapId: scope.id
  }
}

resource vault 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: VaultName
  location: SampleResourceLocation
  properties: {
    accessPolicies: [
      {
        objectId: objid
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
        tenantId: subscription().tenantId
      }
    ]
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}
