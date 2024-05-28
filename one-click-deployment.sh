# Check if .env file exists
if [ -f .env ]; then
    # Export variables from the .env file; make sure the file endings are LF and not CRLF
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Error: .env file not found"
    exit 1
fi

# Make sure that all variables from .env file are set correctly
echo "Checking if all variables are set"
echo "RESOURCE_GROUP: $RESOURCE_GROUP"
echo "REGION: $REGION"
echo "CONTAINER_REGISTRY: $CONTAINER_REGISTRY"
echo "GAME_NAME: $GAME_NAME"

echo "Please login to Azure CLI"
az login

echo "Creating resource group $RESOURCE_GROUP in $REGION"
az group create --name $RESOURCE_GROUP --location $REGION

# Set resource group and region
az configure --defaults group=$RESOURCE_GROUP location=$REGION

echo "Creating Azure Container Registry $ACR_NAME"
az acr create --name $CONTAINER_REGISTRY --sku Basic

echo "Logging into Azure Container Registry $ACR_NAME"
az acr login --name $CONTAINER_REGISTRY

echo "Building Docker image locally"
docker build -t $GAME_NAME .
docker tag $GAME_NAME $CONTAINER_REGISTRY.azurecr.io/$GAME_NAME
docker push $CONTAINER_REGISTRY.azurecr.io/$GAME_NAME

echo "Enabling admin user for the container registry"
az acr update -n $CONTAINER_REGISTRY --admin-enabled true

# Retreive the password for the container registry
echo "Retrieving the password for the container registry"
export ACR_PASSWORD=$(az acr credential show --name $CONTAINER_REGISTRY --query "passwords[0].value" --output tsv)

# Wait some time to be sure that the image is pushed to the container registry and accessible
sleep 30

echo "Create an azure container instance (ACI) to run the container"
az container create --name $GAME_NAME --image $CONTAINER_REGISTRY.azurecr.io/$GAME_NAME --dns-name-label $GAME_NAME --ports 80 --registry-username $CONTAINER_REGISTRY --registry-password $ACR_PASSWORD

echo "Get the public IP address of the container"
az container show --name $GAME_NAME --query "{FQDN:ipAddress.fqdn}" --out table