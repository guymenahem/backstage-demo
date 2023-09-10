# Source: TODO:

#########
# TODO: #
# TODO: #
#########

# Additional Info:
# - Backstage: https://backstage.io
# - Managed Kubernetes K3s Service By Civo: https://youtu.be/SwOIlzXLIw4

#########
# Intro #
#########

# TODO: Intro

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

# TODO: Guy: This is not used anywhere
yq --inplace \
    ".spec.source.repoURL = \"https://github.com/$GITHUB_ORG/backstage-demo\"" \
    argocd/apps/users-api.yaml

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

export GITHUB_TOKEN_ENCODED=$(echo -n $GITHUB_TOKEN | base64)

# TODO: Guy: We should move Backstage manifests to Git so that they
#   can be managed by Argo CD.
#   Otherwise, what's the point of showing Argo CD?
#   To do that, we should not add secrets to manifests.
#   Even if we do not sync backstage with Argo CD, we will be
#   pushing app manifests to Git and, with them, the secrets
#   stored in manifests unencrypted and expose everyone's
#   GitHub tokens.
# TODO: Guy: I suggest using SealedSecrets to generate
#   `backstage-resources/bs-secret.yaml`.
yq --inplace ".data.GITHUB_TOKEN = \"$GITHUB_TOKEN_ENCODED\"" \
    backstage-resources/bs-secret.yaml

yq --inplace \
    ".data.ARGOCD_URL = \"http://argocd.$INGRESS_HOST.nip.io/api/v1/\"" \
    backstage-resources/bs-config.yaml

yq --inplace \
    ".data.CATALOG_LOCATION = \"https://github.com/$GITHUB_ORG/backstage-demo/catalog/app-component.yaml\"" \
    backstage-resources/bs-config.yaml

export BACKSTAGE_URL="backstage.$INGRESS_HOST.nip.io"

yq --inplace ".data.BASE_URL = \"$BACKSTAGE_URL\"" \
    backstage-resources/bs-config.yaml

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

kubectl --namespace backstage get clusters,all

# The the login credentials for Backstage

export DB_PASS=$(kubectl --namespace backstage \
    get secret backstage-app \
    --output jsonpath="{.data.password}")

# Wait for the DB to be created
kubectl --namespace backstage wait pod backstage-1 \
    --for=condition=Ready --timeout=90s

# Repeat the previous command if it errored claiming that the
#   Pod does not exist since that probably means that the Pod
#   was not yet created.

# TODO: Guy: Let's stick with GitOps instead of executing `kubectl`
#   to change the state of something.
# TODO: Viktor: Switch to SchemaHero or Atlas Operator (my choice)
# Allow `app` to create a DB
kubectl exec -it --namespace=backstage backstage-1 -- \
    psql -c "ALTER ROLE app CREATEDB;"

#############
# Backstage #
#############

yq --inplace ".data.POSTGRES_PASSWORD = \"$DB_PASS\"" \
    backstage-resources/bs-secret.yaml

yq --inplace ".data.ARGOCD_AUTH_TOKEN = \"$ARGOCD_AUTH_TOKEN_ENCODED\"" \
    backstage-resources/bs-secret.yaml

# TODO: Guy: We should create an Argo CD app that points to the
#   `backstage-resources` directory once we move generation of
#   secrets to SealedSecrets.
kubectl apply --filename backstage-resources

# TODO: Guy: Uncomment once we're ready to sync Backstage with
#   Argo CD.
#cat argocd/backstage.yaml
#
#cp argocd/backstage.yaml infra/.
#
#git add .
#
#git commit -m "Backstage"
#
#git push

# TODO: Guy: Change to `Observe in Argo CD` once we move it
kubectl --namespace backstage rollout status \
    deployment backstage --watch --timeout=300s

# TODO: Guy: Is there an option to use HTTP (without S) and avoid
#   certificate issues?
echo "https://$BACKSTAGE_URL"

# Open the URL from the output in a browser

#######################
# Destroy The Cluster #
#######################

# This is necessary to avoid pushing secrets to Git until
#   we move to SealedSecrets (or any other alternative).
# TODO: Guy: Remove it after switching to SealedSecrets.
yq --inplace ".data.POSTGRES_PASSWORD = \"SOMETHING\"" \
    backstage-resources/bs-secret.yaml

# This is necessary to avoid pushing secrets to Git until
#   we move to SealedSecrets (or any other alternative).
# TODO: Guy: Remove it after switching to SealedSecrets.
yq --inplace ".data.GITHUB_TOKEN = \"SOMETHING\"" \
    backstage-resources/bs-secret.yaml

# This is necessary to avoid pushing secrets to Git until
#   we move to SealedSecrets (or any other alternative).
# TODO: Guy: Remove it after switching to SealedSecrets.
yq --inplace ".data.ARGOCD_AUTH_TOKEN = \"SOMETHING\"" \
    backstage-resources/bs-secret.yaml

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

rm infra/*.yaml

git add .

git commit -m "Destroy"

git push
