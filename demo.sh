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

# TODO: Convert to `gum` script

# Replace `[...]` with the GitHub organization or a GitHub user
#   if it is a personal account
export GITHUB_ORG=[...]

# TODO: gbase is not installed in MacOS by default.
# TODO: `base64` works on both of my Mac machines (Intel and M1).
# Function to make base64 compatible for Mac OS
# No need to touch it!
function base64_str()
{
    STR=$1

    if [[ "$OSTYPE" == "darwin"* ]]; then
        export BASED64=$(echo $STR'\c' | gbase64 -w 0)
        return
    fi
    export BASED64=$(echo -n "$STR" | base64 -w 0)
}

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

# TODO: Prepare clusters for the attendees and give them
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

# TODO: This is not used anywhere
yq --inplace \
    ".spec.source.repoURL = \"https://github.com/$GITHUB_ORG/backstage-demo\"" \
    argocd/apps/users-api.yaml

yq --inplace \
    ".spec.source.repoURL = \"https://github.com/$GITHUB_ORG/backstage-demo\"" \
    argocd/backstage.yaml

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

# TODO: It's always `app` so there might not be a need to
#   complicate it by retrieving and decoding the secret.
# TODO: Later on, I'll suggest to use SchemaHero or Atlas
#   Operator to manage DB schema and, for that, using a
#   hard-coded user is easier.
export DB_USER_BASED=$(kubectl --namespace backstage \
    get secret backstage-app \
    --output jsonpath="{.data.username}")

# TODO: It's always `app` so there might not be a need to
#   complicate it by retrieving and decoding the secret.
export DB_USER=$(echo $DB_USER_BASED | base64 -d)

export DB_PASS=$(kubectl --namespace backstage \
    get secret backstage-app \
    --output jsonpath="{.data.password}")

# TODO: Remove
export DB_HOST=backstage-rw

# TODO: Remove
export DB_PORT=5432

# TODO: CNPG eventually removes the jobs so if this command
#   is executed late, it might fail.
kubectl wait  job/backstage-1-initdb --for=condition=complete -n backstage --timeout=300s

# Wait for the DB to be created
kubectl --namespace backstage wait pod backstage-1 \
    --for=condition=Ready --timeout=90s

# TODO: Let's stick with GitOps instead of executing `kubectl`
#   to change the state of something.
# TODO: Switch to SchemaHero or Atlas Operator (my choice)
# Allow the DB_USER to create a DB
kubectl exec -it --namespace=backstage backstage-1 -- \
    psql -c "ALTER ROLE $DB_USER CREATEDB;"

#############
# Backstage #
#############

# TODO: There's no need for this since the user, in this setup,
#   does not change (it's always `app`).
yq --inplace ".data.POSTGRES_USER = \"$DB_USER_BASED\"" \
    backstage-resources/bs-secret.yaml

yq --inplace ".data.POSTGRES_PASSWORD = \"$DB_PASS\"" \
    backstage-resources/bs-secret.yaml

# Replace `[...]` with your Github token
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

# TODO: Move this to the `Setup` section
export GITHUB_TOKEN=[...]

export BACKSTAGE_URL="backstage.$INGRESS_HOST.nip.io"

# TODO: This does not work on MacOS without 
base64_str $GITHUB_TOKEN

# TODO: Move this to the `Setup` section
# TODO: We should move Backstage manifests to Git so that they
#   can be managed by Argo CD.
#   Otherwise, what's the point of showing Argo CD?
#   To do that, we should not add secrets to manifests.
#   Even if we do not sync backstage with Argo CD, we will be
#   pushing app manifests to Git and, with them, the secrets
#   stored in manifests unencrypted and expose everyone's
#   GitHub tokens.
# TODO: I suggest using SealedSecrets to generate
#   `backstage-resources/bs-secret.yaml`.
yq --inplace ".data.GITHUB_TOKEN = \"$BASED64\"" \
    backstage-resources/bs-secret.yaml

base64_str "argocd.token="$ARGOCD_AUTH_TOKEN

yq --inplace ".data.ARGOCD_AUTH_TOKEN = \"$BASED64\"" \
    backstage-resources/bs-secret.yaml

# TODO: Move this to the `Setup` section
export ARGOCD_URL="http://argocd.$INGRESS_HOST.nip.io/api/v1/"

# TODO: Move this to the `Setup` section
yq --inplace ".data.ARGOCD_URL = \"$ARGOCD_URL\"" \
    backstage-resources/bs-config.yaml

# TODO: Move this to the `Setup` section
export CATALOG_URL=https://github.com/$GITHUB_ORG/backstage-demo/catalog/app-component.yaml

# TODO: Move this to the `Setup` section
yq --inplace ".data.CATALOG_LOCATION = \"$CATALOG_URL\"" \
    backstage-resources/bs-config.yaml

# TODO: It's always the same port (in this setup) so there's no
#   need to change it.
yq --inplace ".data.POSTGRES_PORT = \"$DB_PORT\"" \
    backstage-resources/bs-config.yaml

# TODO: It's always the same host (in this setup) so there's no
#   need to change it.
yq --inplace ".data.POSTGRES_HOST = \"$DB_HOST\"" \
    backstage-resources/bs-config.yaml

yq --inplace ".data.BASE_URL = \"$BACKSTAGE_URL\"" \
    backstage-resources/bs-config.yaml

export BACKSTAGE_IMAGE=backstage-argocd-workshop:1.0.4

export BACKSTAGE_REGISTRY=ghcr.io/guymenahem/backstage/

export FULL_BACKSTAGE_IMAGE_ID=$BACKSTAGE_REGISTRY""$BACKSTAGE_IMAGE
yq --inplace ".spec.template.spec.containers[0].image = \"$FULL_BACKSTAGE_IMAGE_ID\"" \
              backstage-resources/bs-deploy.yaml

# TODO: We should create an Argo CD app that points to the
#   `backstage-resources` directory once we move generation of
#   secrets to SealedSecrets.
kubectl apply --filename backstage-resources

# TODO: Uncomment once we're ready to sync Backstage with
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

# TODO: Change to `Observe in Argo CD` once we move it
kubectl --namespace backstage rollout status \
    deployment backstage --watch --timeout=300s

# TODO: Guy: Is there an option to use HTTP (without S) and avoid
#   certificate issues?
echo "https://$BACKSTAGE_URL"

# Open the URL from the output in a browser

#######################
# Destroy The Cluster #
#######################

# TODO: This is necessary to avoid pushing secrets to Git until
#   we move to SealedSecrets (or any other alternative).
yq --inplace ".data.POSTGRES_PASSWORD = \"SOMETHING\"" \
    backstage-resources/bs-secret.yaml

# TODO: This is necessary to avoid pushing secrets to Git until
#   we move to SealedSecrets (or any other alternative).
yq --inplace ".data.GITHUB_TOKEN = \"SOMETHING\"" \
    backstage-resources/bs-secret.yaml

# TODO: Argo CD auth token is temporary so it should not be a big
#   deal to push it to Git, but GitHub might reject the commit
#   that contains a secret.
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
