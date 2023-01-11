#!/bin/bash

# -----------------

# Allow Prometheus process to view the openshift-operators namespace
kubectl apply -f prometheus-roles-for-openshift-operators.yaml -n openshift-operators
kubectl apply -f prometheus-roles-for-gitops-ns.yaml -n gitops

# -----------------
echo 
echo "* Kick off an OLM install of Grafana, and wait for it to complete"


kubectl create ns grafana > /dev/null 2>&1

kubectl apply -f grafana-operator-group.yaml -n grafana
kubectl apply -f grafana-subscription.yaml -n grafana

echo
echo "* Waiting for Grafana CRDs to exist"

while : ; do
  kubectl get customresourcedefinition/grafanas.integreatly.org  > /dev/null 2>&1 && break
  sleep 1s
done

# -----------------


# Extract the cluster domain from another route

export HOSTNAME=`kubectl get route/grafana-route -n grafana -o yaml  | grep "    host:" | cut -c11-`

echo
echo "* Grafana route is: https://$HOSTNAME"
echo "  - See 'grafana-cr.yaml' for admin login/password"
echo

TMP_DIR=`mktemp -d`

# Substitute the cluster domain into the Grafana Ingress CR
cp -f grafana-cr.yaml $TMP_DIR/grafana-cr-resolved.yaml
sed -i 's/HOSTNAME/'$HOSTNAME'/g' $TMP_DIR/grafana-cr-resolved.yaml

kubectl apply -f $TMP_DIR/grafana-cr-resolved.yaml -n grafana

rm -f $TMP_DIR/grafana-cr-resolved.yaml

# The kubectl equivalent to: 'oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana-serviceaccount'
kubectl apply -f grafana-cluster-role-binding.yaml -n grafana

# -----------------
echo
echo "* Waiting for Grafana service account token secret to exist"
while : ; do
  kubectl get secrets -n grafana | grep "grafana-serviceaccount-token"  > /dev/null 2>&1 && break
  sleep 1s
done

echo
echo "* Applying GrafanaDataSource, using Grafana Service Account Token"

GRAFANA_SECRET=`kubectl -n grafana get secrets | grep "grafana-serviceaccount-token" |  cut -d ' ' -f 1`

GRAFANA_SA_TOKEN=`kubectl -n grafana get secret $GRAFANA_SECRET -o jsonpath={.data.token} | base64 -d`

cp -f grafana-data-source.yaml  $TMP_DIR/grafana-data-source-resolved.yaml

sed -i 's/GRAFANA_SA_TOKEN/'$GRAFANA_SA_TOKEN'/g' $TMP_DIR/grafana-data-source-resolved.yaml

kubectl apply -f $TMP_DIR/grafana-data-source-resolved.yaml

rm -f $TMP_DIR/grafana-data-source-resolved.yaml

# This section was based on https://www.redhat.com/en/blog/custom-grafana-dashboards-red-hat-openshift-container-platform-4

# -----------------
echo
echo "* Create Argo dashboards and GitOps Operator ServiceMonitor"

kubectl apply -f argo-grafana-dashboard-cm.yaml
kubectl apply -f grafana-argo-dashboard.yaml

# Create a ServiceMonitor for GitOps Operator, in the openshift-gitops namespace
# - This SHOULD instead be created in the openshift-operators namespace (which is where the gitops-operator lives),
#   but the prometheus-operator process has a hardcoded list of namespaces that it checks, openshift-operators
#   is not on it.

kubectl apply -f openshift-operators-service-monitor.yaml -n openshift-gitops

# -----------------



