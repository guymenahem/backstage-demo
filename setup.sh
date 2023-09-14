#!/bin/sh

set -e

rm -f kubeconfig*.yaml

rm -f .env

gum style \
        --foreground 212 --border-foreground 212 --border double \
        --margin "1 2" --padding "2 4" \
        'Backstage Demo Setup'

echo "
## You will need following tools installed:
|Name            |Required             |More info                                          |
|----------------|---------------------|---------------------------------------------------|
|gitHub CLI      |Yes                  |'https://cli.github.com/'                          |
|yq              |Yes                  |'https://github.com/mikefarah/yq#install'          |
|kubeseal        |Yes                  |'https://github.com/bitnami-labs/sealed-secrets#kubeseal'|
" | gum format

gum confirm "
Do you have those tools installed?
" || exit 0

GITHUB_ORG=$(gum input \
    --placeholder "Which GitHub organization do you want to use?" \
    --value "$GITHUB_ORG")
echo "export GITHUB_ORG=$GITHUB_ORG" >> .env

gh repo fork vfarcic/backstage-demo --clone --remote \
    --org $GITHUB_ORG

cd backstage-demo

export INGRESS_CLASS=$(kubectl get ingressclasses \
    --output jsonpath="{.items[0].metadata.name}")
echo "export INGRESS_CLASS=$INGRESS_CLASS" >> .env

export INGRESS_HOST=$(\
    kubectl --namespace kube-system get service traefik \
    --output jsonpath="{.status.loadBalancer.ingress[0].ip}")
echo "export INGRESS_HOST=$INGRESS_HOST" >> .env

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

gum style \
        --foreground 212 --border-foreground 212 --border double \
        --margin "1 2" --padding "2 4" \
        'Create a token in GitHub - https://github.com/settings/tokens' \
        'or by navigating to Settings -> Developer Settings (left panel) ->' \
        'Personal Access Token -> Tokens (Classic) -> Generate new token' \
        '' \
        'Required permissions:' \
        '- repo' \
        '- read:org' \
        '- read:user' \
        '- user:email' \
        '- workflow'

GITHUB_TOKEN=$(gum input --placeholder "GitHub token" --value "$GITHUB_TOKEN" --password)
echo "export GITHUB_TOKEN=$GITHUB_TOKEN" >> .env

yq --inplace \
    ".data.ARGOCD_URL = \"http://argocd.$INGRESS_HOST.nip.io/api/v1/\"" \
    backstage-resources/bs-config.yaml

yq --inplace \
    ".data.CATALOG_LOCATION = \"https://github.com/$GITHUB_ORG/backstage-demo/catalog/app-component.yaml\"" \
    backstage-resources/bs-config.yaml

export BACKSTAGE_URL="backstage.$INGRESS_HOST.nip.io"
echo "export BACKSTAGE_URL=$BACKSTAGE_URL" >> .env

yq --inplace ".data.BASE_URL = \"$BACKSTAGE_URL\"" \
    backstage-resources/bs-config.yaml
