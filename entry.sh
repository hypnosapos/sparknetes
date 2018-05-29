#!/usr/bin/env bash

set -e

function activate_account {
  [ ! -f $GCP_CREDS_FILE ] || ( echo "Required a gcp.json file with GCP credentials (set env GCP_CREDS_FILE)" && exit 1 )
  [ -z "$GCP_CLUSTER_NAME" ] && echo "Env variable GCP_CLUSTER_NAME not defined (the GKE cluster name)" && exit 1
  [ -z "$GCP_ZONE" ] && echo "Env variable GCP_ZONE not defined (the zone of GCP)" && exit 1
  [ -z "$GCP_PROJECT_ID" ] && echo "Env variable GCP_PROJECT_ID not defined (the id of GCP project)" && exit 1
  gcloud auth activate-service-account --key-file $GCP_CREDS_FILE
  gcloud container clusters get-credentials $GCP_CLUSTER_NAME --zone $GCP_ZONE --project $GCP_PROJECT_ID
}

function admin_creds {
  [ -z "$GCP_CLUSTER_ADMIN_PASS" ] && echo "Env variable GCP_CLUSTER_ADMIN_PASS not defined" && exit 1
  kubectl config set-credentials gke_${GCP_PROJECT_ID}_${GCP_ZONE}_${GCP_CLUSTER_NAME} --username=admin --password=$GCP_CLUSTER_ADMIN_PASS
}

function tiller {
    kubectl -n kube-system create sa tiller
    kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
    helm init --wait --service-account tiller
}

activate_account && admin_creds && tiller