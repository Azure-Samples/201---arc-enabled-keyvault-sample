
# 201 sample - Accessing private ACR from on-prem K8S

## Scenario
A developer working with an Arc-enabled K8S cluster would like to deploy a container whose image is stored in a private ACR. The access credential of this ACR is stored in Azure KeyVault (AKV), but the developer cannot access it directly due to security restrictions.

Arc-Enabled KeyVault is an Arc extension that can be deployed to Arc-enabled clusters to retrieve secrets from AKV. The developer employs Arc-Enabled KeyVault and creates a K8S secret object on the on-prem K8S cluster, which is used by the cluster to pull images from the private ACR.

## Prerequisites

### Required
- A native K8S cluster connected to Arc. The Azure Arc VS code extension can help to create an AKS EE cluster and connect to Arc if needed.
- [AZS CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/reference)
- [Helm](https://helm.sh/docs/intro/install/)


### Recommended
- VS code with [Azure Arc Extension](https://marketplace.visualstudio.com/search?term=azure%20arc&target=VSCode&category=All%20categories&sortBy=Relevance)
- An AKS or AKS EE cluster that's connected to Arc to minimize compatibility issues
  > The Azure Arc Extension can help creating AKS EE clusters and connecting compatible K8S clusters to Arc.

## Steps
> Note: Arc-enabled KV steps provided here are summerized from the [full and most up-to-date instructions](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/tutorial-akv-secrets-provider). Check it out if you'd like to learn more.

1. A service principal with password secret is required.
    - If you don't have one yet, follow [these steps](https://learn.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#register-an-application-with-azure-ad-and-create-a-service-principal) to create an SP with password (not with certificate).
    - If you'd like to reuse an existing SP, make sure it has a password secret. You can associate a new secret with your existing SP with these [instructions](https://learn.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal#option-3-create-a-new-application-secret).
  
    Please take note of the Client ID (a.k.a., App ID), tenantID, service principal object ID and Client Secret generated in this step.

2. Use the client ID and client secret **value** as plain text from the first step to create a Kubernetes secret on the connected cluster.
    ```
    kubectl create secret generic secrets-store-creds --from-literal clientid="<client-id>" --from-literal clientsecret="<client secret value>"
    ```

3. Create a label from the created secret:
    ```
    kubectl label secret secrets-store-creds secrets-store.csi.k8s.io/used=true
    ```

4. Create Azure and Arc denependencies such as Azure KeyVault (AKV) with access policy, Azure Container Registry (ACR) with access token, and Arc-enabled KeyVault extension.
    - **Recommended**: use bicep included in the sample to automatically create all Azure and Arc resources. To do that, fill out the [main.parameters.json](.\bicep\infra\main.parameters.json) file and deploy the bicep template using the below command in the bicep folder and follow the prompt to create an environment name, select a subscription/location and so on. Please note that some resource names in main.parameters.json must be globally unique. *If you need to rerun bicep file, be aware that the accessPolicies in key vault and the token passwords in Azure container registry may be reset. Please double check before preceeding to the next step.*

        NOTE: the objid value is the service principal object Id, not the application object Id. There're two ways to properly retrieve this Id:    
        - **Recommended**: using AZ CLI, specify the display name of the service principal
            ```powershell
            (az ad sp list --display-name <SP display name> | ConvertFrom-Json).id
            ```
        
        - Using Azure Portal <br/>
        Navigate to **Enterprise Application** (a.k.a., service principal) and locate your service principal, in the overview tab make a copy of the Object ID field. It is important to NOT confuse with **App regsitrations** (a.k.a., applications).
            

      | Properties | Descriptions |
      |-|-|
      | ArcK8sName | Arc-enabled cluster name |
      | ClusterResourceGroup | Arc-enabled cluster resource group |
      | SampleResourceGroup | Resource group to manage sample resources |
      | SampleResourceLocation | Sample resource location, must be one of the locations available from Azure |
      | VaultName | The name of the Azure KeyVault |
      | objid | The object Id of the service principal.|
      | acrName | The name of the Azure Container Registry (ACR) |
      | tokenName | The name of the ACR token that allows pulling images from the K8S cluster |

      ```powershell
      cd .\bicep
      azd provision
      ```

    - **Advanced**: If you'd like to define and create ACR token manually without using the token access permissions defined in the bicep file, you could create a new scope to manage access manually. Take a note of the username and password and define the token scope yourself or use the default scopes. Make sure the scope covers the image you would use in the k8s deployment. It should have the permission to pull the requied image at least.<br/>
![HowToCreateAToken](https://raw.githubusercontent.com/Azure-Samples/arc-enabled-keyvault-sample/main/screenshots/Token.png)

<br/>

5. The K8S cluster requires a password generated for ACR token, which can be done through Azure portal or powershell.
    - **Recommended**: From powershell console
      Specify the ACR name and token name either created from bicep or managed by yourself.
      ```powershell
      $acrName = "<your ACR name>"
      $tokenName = "<your ACR token name>"
      $passwords = az acr token credential generate --registry $acrName --name $tokenName | ConvertFrom-Json
      $password = $passwords.passwords[0].value
      ```
   
    - From Azure Portal
    ![HowToGeneratePwd](https://raw.githubusercontent.com/Azure-Samples/arc-enabled-keyvault-sample/main/screenshots/Pwd.png) <br />
    record the password in base64 string for later use.
    
6. Having acquired the password, generate the ACR credential with the following command and take not of the credential:
      ```powershell
      $tokenName = "<your ACR token name>"
      $password = "<password retrieved from the previous step>"
      $acrName = "<your ACR name>"

      # The ACR URL from the credential generated must be the same as the full image name. Convert to all lower case to be safe.
      $acrUrl = "$($acrName.ToLower()).azurecr.io"
      $stringInBytes = [System.Text.Encoding]::UTF8.GetBytes("$tokenName`:$password")
      $stringEncoded = [System.Convert]::ToBase64String($stringInBytes)
      $credential = "{`"auths`":{`"$acrUrl`":{`"auth`":`"$stringEncoded`"}}}"
      $credential
      ```

      The result should look like the following:
      ```json
      {"auths":{"sample.azurecr.io":{"auth":"dXNlcm5hbWU6cGFzc3dvcmQ="}}}
      ```

7. Save the whole json string generated in the previous step as a secret to the AKV created in bicep deployment. You may need to assign yourself access policies in order to create secrets. Take note of the secret name. <br />
![HowToCreateASecret](https://raw.githubusercontent.com/Azure-Samples/arc-enabled-keyvault-sample/main/screenshots/KV.png)

8. Push an image to the ACR
    > Note: the credential created in the previous step is based on the token that has '_repositories_pull' privilege as defined in [resource.bicep](.\bicep\infra\resource.bicep) and is intended for the on-prem K8S cluster to pull images from the ACR. To push an image to the ACR you might need to login using your own Azure credentials, or enable Azure KeyVault admin user to login.

    Make sure you've logged in to the ACR with a user that has push privilege. There're two alternatives to login:

    - **Recommended**: using your Azure credentials
        ```powershell
        az login
        az acr login --name <acrName>
        ```

    - Using ACR admin account <br/>
        Follow the [instructions](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-authentication?tabs=azure-cli#admin-account) to enable ACR admin account, and login with the admin user credentials found from Azure portal.

        ```powershell
        docker login $acrUrl -u <admin username> -p <admin user password>
        ```

        There will be some security warnings about using passwords to login, which is why Azure credentials is recommended. However, it won't affect functionalities using the ACR so you can ignore that from the time being.
    
    Make sure your docker engine is running. A typical full image name looks like this
    
    ```
    sample.azurecr.io/samplerepo/ubuntu:latest
    ```

    To illustrate the terminology used in the rest of the sample with the example full image name above:
    | Segment | Descrpition | 
    |-|-|
    | sample | The ACR name in lower case, used to identify your ACR resource on Azure |
    | sample.azurecr.io | The ACR URL, the endpoint of ACR |
    | samplerepo | The repository name, ACR supports fine-grain access control at the repository level, so it is recommended to push your images under repositories |
    | ubuntu | The image name |
    | latest | The image tag. It can be almost any string you decide, and the most common use of image tag is to indicate different versions of your image. The "latest" tag is created automatically even if you don't specify a tag. |
    
    The following commands pulls a hello-world image from docker.io and push to ACR.

    ```powershell
    # e.g., sample.azurecr.io/samplerepo/ubuntu:latest 
    $repositoryName = "<your repo name>"
    $imageName = "$acrUrl/$repositoryName/ubuntu`:latest" 
    docker pull ubuntu:latest
    docker tag ubuntu:latest $imageName
    docker push $imageName
    ```

9. Go to [values.yaml](.\chart\values.yaml) and fill in the parameters as prompted in the place holder. Required fields include:

    | Properties | Descriptions |
    |-|-|
    | imageName | Full image name that must match the casing of the credential generated in step 6. To be safe, convert the full image name to all lower case, e.g., sample.azurecr.io/samplerepo/ubuntu:latest |
    | keyvaultName | The KeyVault name |
    | keyvaultSecretName | The secret name that contains ACR credentials in the KeyVault |
    | tenantId | The tenant id of subscription |

    Please do not modify the default value of the "secretName" property, it must be the name of the secret created in step 2, which should be "secrets-store-creds" in this sample.

10. Install the chart

    ```bash
    helm install .\chart\ --generate-name
    ```

    If you accidentally filled in incorrect information to values.yaml and would like to try again, you can find the helm install with:

    ```bash
    helm ls
    ```

    and (Recommended) upgrade the installation with:

    ```bash
    helm upgrade <char name> <char repo>
    ```

    or remove the installation and install again with:

    ```bash
    helm uninstall <char name>
    helm install <chat repo> --generate-name
    ```

    For example:
    ```bash
    helm upgrade chart-1692064686 .\chart
    ```
    or

    ```bash
    helm uninstall chart-1692064686 
    helm install .\chart\ --generate-name
    ```

## Validation
A pod with prefix "chart" should be running in default namespace. Check your pod status with:
```bash
kubectl get pods
```

The output should look like this:
```
NAME                             READY   STATUS    RESTARTS   AGE
arc-kv-sample-5fd9bbb864-zzmpq   1/1     Running   0          19s
```

Inspect container logs with:
```powershell
kubectl logs <podName>
```

For example:

```powershell
kubectl logs arc-kv-sample-5fd9bbb864-zzmpq
```

And you should see a message saying "Sleep tight!"

## Cleanup
Uninstall the chart 

```bash
# Find the installed chart name
helm ls

# Uninstall the chart
helm uninstall <char name>
```

You can remove Azure resources created for this sample by deleting the entire resrouce group from Portal.
