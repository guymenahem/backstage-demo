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

# TODO: Prepare clusters for the attendees and give them
#   kube config.
# Skip the command that follows if you chose to create a cluster
#   in a different provider (other than Civo).
# Please watch https://youtu.be/SwOIlzXLIw4 if you are not
#   familiar with Civo.
civo kubernetes create dot --size g4s.kube.medium \
    --remove-applications=Traefik-v2-nodeport \
    --applications civo-cluster-autoscaler,Traefik-v2-loadbalancer \
    --nodes 1 --region NYC1 --yes --wait

# Skip the command that follows if you chose to create a cluster
#   in a different provider (other than Civo).
export KUBECONFIG=$PWD/kubeconfig.yaml

# Skip the command that follows if you chose to create a cluster
#   in a different provider (other than Civo).
civo kubernetes config dot --region NYC1 \
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
yq --inplace ".server.ingress.ingressClassName = \"$INGRESS_CLASS\"" \
    argocd/helm-values.yaml

yq --inplace \
    ".server.ingress.hosts[0] = \"argocd.$INGRESS_HOST.nip.io\"" \
    argocd/helm-values.yaml

yq --inplace \
    ".spec.source.repoURL = \"https://github.com/$GITHUB_ORG/backstage-demo\"" \
    argocd/apps.yaml

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

cat argocd/apps.yaml

kubectl apply --filename argocd/apps.yaml

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

export DB_USER=$(kubectl --namespace backstage \
    get secret backstage-app \
    --output jsonpath="{.data.username}" | base64 --decode)

export DB_PASS=$(kubectl --namespace backstage \
    get secret backstage-app \
    --output jsonpath="{.data.password}" | base64 --decode)

export DB_HOST=backstage-rw

export DB_PORT=5432

#############
# Backstage #
#############

cat argocd/backstage.yaml

cp argocd/backstage.yaml infra/.

git add .

git commit -m "Backstage"

git push

# Observe in Argo CD

echo "http://backstage.$INGRESS_HOST.nip.io"

# Open the URL from the output in a browser

#######################
# Destroy The Cluster #
#######################

civo kubernetes remove dot --region NYC1 --yes

rm -f $KUBECONFIG

sleep 10

civo firewall ls --region NYC1 --output custom --fields "name" | grep dot \
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
