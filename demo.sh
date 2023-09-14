#########
# Setup #
#########

# TODO: Viktor: Convert to `gum` script

# Replace `[...]` with the GitHub organization or a GitHub user
#   if it is a personal account
export GITHUB_ORG=[...]

# Watch https://youtu.be/BII6ZY2Rnlc if you are not familiar
#   with GitHub CLI
gh repo fork vfarcic/backstage-demo --clone --remote \
    --org $GITHUB_ORG

cd backstage-demo

gh repo set-default

# Select the fork as the default repository

# Create a Kubernetes cluster with an Ingress controller
# The commands that follow will create a cluster in Civo, but any
#   other should do.

# Replace `[...]` with the name of the cluster.
# Please make sure it is unique (e.g., your username, the name
#   of your pet, etc.)
export CLUSTER_NAME=[...]

# TODO: Viktor: Prepare clusters for the attendees and give them
#   kube config.
# Skip the command that follows if you chose to create a cluster
#   in a different provider (other than Civo).
# If you're creating a cluster yourself, make sure that an 
#   Ingress controller is installed.
# Please watch https://youtu.be/SwOIlzXLIw4 if you are not
#   familiar with Civo.
civo kubernetes create $CLUSTER_NAME --size g4s.kube.medium \
    --remove-applications=Traefik-v2-nodeport \
    --applications civo-cluster-autoscaler,Traefik-v2-loadbalancer \
    --nodes 1 --region NYC1 --yes --wait

# Skip the command that follows if you chose to create a cluster
#   in a different provider (other than Civo).
export KUBECONFIG=$PWD/kubeconfig.yaml

# Skip the command that follows if you chose to create a cluster
#   in a different provider (other than Civo).
civo kubernetes config $CLUSTER_NAME --region NYC1 \
    --local-path $KUBECONFIG --save

# Skip the command that follows if you chose to create a cluster
#   in a different provider (other than Civo).
chmod 400 $KUBECONFIG

export INGRESS_CLASS=$(kubectl get ingressclasses \
    --output jsonpath="{.items[0].metadata.name}")

# Execute only if NOT using Civo
# Replace `[...]` with the external IP of the Ingress
#   Service.
export INGRESS_HOST=[...]

# Execute only if using Civo
export INGRESS_HOST=$(\
    kubectl --namespace kube-system get service traefik \
    --output jsonpath="{.status.loadBalancer.ingress[0].ip}")

echo $INGRESS_HOST

# Repeat the `export` command if the output is empty

# Install `yq` from https://github.com/mikefarah/yq if you do not have it already
yq --inplace \
    ".server.ingress.ingressClassName = \"$INGRESS_CLASS\"" \
    argocd/helm-values.yaml

yq --inplace \
    ".server.ingress.hosts[0] = \"argocd.$INGRESS_HOST.nip.io\"" \
    argocd/helm-values.yaml

yq --inplace \
    ".spec.source.repoURL = \"https://github.com/$GITHUB_ORG/backstage-demo\"" \
    argocd/production-apps.yaml

yq --inplace \
    ".spec.source.repoURL = \"https://github.com/$GITHUB_ORG/backstage-demo\"" \
    argocd/production-infra.yaml

yq --inplace \
    ".spec.source.repoURL = \"https://github.com/$GITHUB_ORG/backstage-demo\"" \
    argocd/users-api.yaml

yq --inplace \
    ".spec.source.repoURL = \"https://github.com/$GITHUB_ORG/backstage-demo\"" \
    argocd/backstage.yaml

# Create a token in GitHub - https://github.com/settings/tokens
# or by navigating to Settings -> Developer Settings (left panel) -> 
# Personal Access Token -> Tokens (Classic) -> Generate new token
# 
# Required permissions: 
#   - repo
#   - read:org
#   - read:user
#   - user:email
#   - workflow

# Replace `[...]` with your Github token
export GITHUB_TOKEN=[...]

yq --inplace \
    ".data.ARGOCD_URL = \"http://argocd.$INGRESS_HOST.nip.io/api/v1/\"" \
    backstage-resources/bs-config.yaml

yq --inplace \
    ".data.CATALOG_LOCATION = \"https://github.com/$GITHUB_ORG/backstage-demo/catalog/app-component.yaml\"" \
    backstage-resources/bs-config.yaml

export BACKSTAGE_URL="backstage.$INGRESS_HOST.nip.io"

yq --inplace ".data.BASE_URL = \"$BACKSTAGE_URL\"" \
    backstage-resources/bs-config.yaml

# Install `kubeseal` by following the instructions at
#   https://github.com/bitnami-labs/sealed-secrets#kubeseal

###########
# Argo CD #
###########

helm upgrade --install argocd argo-cd \
    --repo https://argoproj.github.io/argo-helm \
    --namespace argocd --create-namespace \
    --values argocd/helm-values.yaml --wait

echo "http://argocd.$INGRESS_HOST.nip.io"

# Open the URL from the output in a browser
# Use `admin` as the user and `admin123` as the password

cat argocd/production-apps.yaml

cat argocd/production-infra.yaml

kubectl apply --filename argocd/production-infra.yaml

kubectl apply --filename argocd/production-apps.yaml

export ARGOCD_ADMIN_PASSWORD=admin123

argocd login --insecure --port-forward --insecure \
    --username admin --password $ARGOCD_ADMIN_PASSWORD \
    --port-forward-namespace argocd --grpc-web --plaintext

# Generate API auth token for ArgoCD
export ARGOCD_AUTH_TOKEN=$(argocd account generate-token \
    --port-forward --port-forward-namespace argocd)

export ARGOCD_AUTH_TOKEN_ENCODED=$(
    echo -n "argocd.token=$ARGOCD_AUTH_TOKEN" | base64)

##############
# PostgreSQL #
##############

cat argocd/cnpg.yaml

cp argocd/cnpg.yaml infra/.

git add .

git commit -m "CPNG"

git push

# Observe CNPG rollout in Argo CD UI

kubectl --namespace cnpg-system get all

cat argocd/backstage-postgresql.yaml

cp argocd/backstage-postgresql.yaml infra/.

git add .

git commit -m "Backstage PostgreSQL"

git push

# Observe PostgreSQL rollout in Argo CD UI

kubectl --namespace backstage get clusters

# The the login credentials for Backstage

export DB_PASS=$(kubectl --namespace backstage \
    get secret backstage-app \
    --output jsonpath="{.data.password}" | base64 --decode)

# Wait for the DB to be created
kubectl --namespace backstage wait pod backstage-1 \
    --for=condition=Ready --timeout=90s

# Repeat the previous command if it errored claiming that the
#   Pod does not exist since that probably means that the Pod
#   was not yet created.

kubectl exec -it --namespace=backstage backstage-1 -- \
    psql -c "\du"

#################
# SealedSecrets #
#################

cat argocd/sealed-secrets-app.yaml

cp argocd/sealed-secrets-app.yaml infra/.

git add infra

git commit -m "Deploy sealed secrets controller"

git push

# Observe SealedSecrets rollout in Argo CD UI

#############
# Backstage #
#############

cat backstage-resources/*.yaml

kubectl --namespace backstage \
    create secret generic backstage-secrets \
    --from-literal POSTGRES_USER=app \
    --from-literal POSTGRES_PASSWORD=$DB_PASS \
    --from-literal GITHUB_TOKEN=$GITHUB_TOKEN \
    --from-literal ARGOCD_AUTH_TOKEN=$ARGOCD_AUTH_TOKEN \
    --dry-run=client --output json

kubectl --namespace backstage \
    create secret generic backstage-secrets \
    --from-literal POSTGRES_USER=app \
    --from-literal POSTGRES_PASSWORD=$DB_PASS \
    --from-literal GITHUB_TOKEN=$GITHUB_TOKEN \
    --from-literal ARGOCD_AUTH_TOKEN=$ARGOCD_AUTH_TOKEN \
    --dry-run=client --output yaml \
    | kubeseal --controller-namespace kubeseal \
    | tee backstage-resources/bs-secret.json

cat argocd/backstage.yaml

cp argocd/backstage.yaml infra/.

git add .

git commit -m "Deploy Backstage"

git push

# Observe the Backstage rollout in ArgoCD

kubectl --namespace backstage get all,secrets

echo "https://$BACKSTAGE_URL"

# Open the URL from the output in a browser

#################
# Deploy An App #
#################

cat users-api/deployment.yaml

cat argocd/users-api.yaml

cp argocd/users-api.yaml apps/.

git add .

git commit -m "deploy users-api"

git push

kubectl get all

# TODO: Guy: Show the app in Backstage

#######################
# Destroy The Cluster #
#######################

civo kubernetes remove $CLUSTER_NAME --region NYC1 --yes

rm -f $KUBECONFIG

sleep 10

civo firewall ls --region NYC1 --output custom --fields "name" | grep $CLUSTER_NAME \
    | while read FIREWALL; do
    civo firewall rm $FIREWALL --region NYC1 --yes
done

civo volume ls --region NYC1 --dangling --output custom --fields "name" \
    | while read VOLUME; do
    civo volume rm $VOLUME --region NYC1 --yes
done

rm apps/*.yaml

rm infra/*.yaml

git add .

git commit -m "Destroy"

git push
