#!/bin/bash
# Fetch OIDC configuration info using OpenShift secrets

# Prompts user for name and returns
promptuser() {
  read -p "Missing $1, please enter name: " -r
  if [[ -z "$REPLY" ]]; then echo "Error: Missing value for $1, exiting" >&2 && exit 1; fi
  echo "$REPLY"
}

# 0. Check CLI exists, we are logged in, and have permissions
oc_version=$(oc version)
rtn_code=$?
if [[ -z "$oc_version" || rtn_code -eq 127 ]]; then
  echo "OpenShift CLI not installed, check your path or go to https://access.redhat.com/downloads/content/290"
  exit 1
fi
set -e
# 0.2 Check for admin permissions
if [[ $(oc auth can-i '*' '*') != 'yes' ]]; then echo "Insufficient permissions to install. Please copy and paste Login command with permissions and try again." && exit 1; fi
# Try and find core & manage projects
namespaces=$(oc get namespaces -oname | sed -e 's/^.*\///')
core_namespace=$(promptuser "Core namespace")
manage_namespace=$(promptuser "Manage namespace")
instance_id=$(echo $core_namespace | grep -Po -- "(?<=-).*(?=-)" || promptuser "Workspace/instance ID")
echo "Core namespace: $core_namespace"
echo "Manage namespace: $manage_namespace"

oc project "$manage_namespace"
secrets=$(oc get secrets -oname | sed -e 's/^.*\///') # remove leading '***/'

echo "Discovering secrets/configuration for OIDC extraction..."
coreidp_binding=$(echo "$secrets" | grep -Pm 1 "\-coreidp-system-binding" || promptuser "coreidp-system-binding Secret")

oauth_url=$(oc get secret $coreidp_binding --template='{{.data.url|base64decode}}')
oauth_url="https://auth.dev2.apps.osp-epg4i.gm.com/oidc/endpoint/MaximoAppSuite"
echo $oauth_url
oauth_username=$(oc get secret $coreidp_binding -o jsonpath="{.data['oauth-admin-username']}" | base64 -d)
oauth_password=$(oc get secret $coreidp_binding -o jsonpath="{.data['oauth-admin-password']}" | base64 -d)
domain_name=$(echo $oauth_url | grep -Pom 1 "(?<=https://auth.)[^/]*" || promptuser "domain name")
apps_domain_name=$(echo $domain_name | grep -Pom 1 "apps[^/]*" || promptuser "apps domain name")
app_url="https://$CLIENT_ID-$manage_namespace.$apps_domain_name"
echo "$app_url"
exit 0
echo "Fetching OIDC info..."
oauth_basic="${oauth_username}:${oauth_password}"
# curl -kf -o discovery.json -u "$oauth_basic" "$oauth_url/.well-known/openid-configuration"
echo "Fetched OIDC discovery info to: discovery.json"
# curl -kf -o "clients.json" -u "$oauth_basic" "$oauth_url/registration"
# Try to use python to prettify JSON, but ignore errors if Python is missing
# cat clients.json | py -m json.tool > clients.tmp.json && mv clients.tmp.json clients.json || true
echo "Fetched OIDC client info to: clients.json"
set +x
set +e