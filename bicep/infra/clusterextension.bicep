@description('The name of the connected k8s to have KV extension.')
param ArcK8sName string

resource k8s 'Microsoft.Kubernetes/connectedClusters@2022-10-01-preview' existing = {
  name: ArcK8sName
}
  
resource symbolicname 'Microsoft.KubernetesConfiguration/extensions@2022-11-01' = {
  name: 'akvsecretsprovider'
  scope: k8s
  properties: {
    autoUpgradeMinorVersion: true
    configurationProtectedSettings: {}
    configurationSettings: {
      'secrets-store-csi-driver.syncSecret.enabled' : 'true'
      'secrets-store-csi-driver.enableSecretRotation' : 'true'
    }
    extensionType: 'Microsoft.AzureKeyVaultSecretsProvider'
    releaseTrain: 'Stable'
    scope: {
      cluster: {
        releaseNamespace: 'kube-system'
      }
    }
  }
}
