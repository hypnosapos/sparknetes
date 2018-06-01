# Sparknetes
[![Build status](https://circleci.com/gh/hypnosapos/sparknetes/tree/master.svg?style=svg)](https://circleci.com/gh/hypnosapos/sparknetes/tree/master)
[![sparknetes layers](https://images.microbadger.com/badges/image/hypnosapos/sparknetes.svg)](https://microbadger.com/images/hypnosapos/sparknetes)
[![sparknetes version](https://images.microbadger.com/badges/version/hypnosapos/sparknetes.svg)](https://microbadger.com/images/hypnosapos/sparknetes)
[![sparknetes-gke layers](https://images.microbadger.com/badges/image/hypnosapos/sparknetes-gke.svg)](https://microbadger.com/images/hypnosapos/sparknetes-gke)
[![sparknetes-gke version](https://images.microbadger.com/badges/version/hypnosapos/sparknetes-gke.svg)](https://microbadger.com/images/hypnosapos/sparknetes-gke)

Spark on kubernetes. Based on official site of spark 2.3 at https://spark.apache.org/docs/2.3.0/running-on-kubernetes.html

Tests were run over GKE service.

## Publish your docker images

In order to get base docker images to use with spark submit command we may use this intermediate docker images:

```bash
make sparknetes-build sparknetes-gke-build
```
> NOTE: This process may take you several minutes (~20 mins, under the wood there is a maven packaging task running). Take a look at Makefile file to view default values and other variables.

We've left docker images available under the dockerhub org [dockerhub/hypnosapos](https://hub.docker.com/r/hypnosapos/) (powered by CircleCI)

You could push your own images as well by:
```sh
DOCKER_ORG=<your_docker_registry_org_here> make sparknetes-push sparknetes-gke-push
```

## Kubernetes cluster

We've tried pocs on GKE service. This is the command to get up a cluster via gcloud sdk:
```sh
gcloud beta container --project "<you_gcp_project>" clusters create "spark" --zone "europe-west1-b" --username "admin" --cluster-version "1.8.10-gke.0" \
--machine-type "n1-standard-4" --image-type "COS" --disk-type "pd-standard" --disk-size "100" \
--scopes "https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol",\
"https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
--num-nodes "5" --enable-cloud-logging --enable-cloud-monitoring --network "default" \
--subnetwork "default" --addons HorizontalPodAutoscaling,HttpLoadBalancing,KubernetesDashboard --enable-autorepair
```

If you prefer use another cluster on other cloud or infrastructure (even local station), it's up to you.

## Launch examples

Before run examples you must provide a kuberntes cluster ready for use.

Til now we've try examples only by GKE service, once a cluster is ready run the "sparknetes-gke*" subcommands with the suitable values of GCP variables:

```bash
GCP_ZONE=<gcp_zone> \
GCP_PROJECT_ID=<gcp_project_id> \
GCP_CLUSTER_NAME=spark \
GCP_CLUSTER_ADMIN_PASS=******** \
GCP_CREDENTIALS=<path_file_gcp.json> \
GCP_CLUSTER_ADMIN_PASS=*********** \
make sparknetes-gke sparknetes-gke-bootstrap sparknetes-gke-proxy
```

This container will be use to launch examples through the internel proxy URL (http://127.0.0.1:8001). Make sure that proxy is alive by:
```sh
docker top sparknetes-gke
PID                 USER                TIME                COMMAND
8980                root                0:00                bash
9422                root                0:00                kubectl proxy
```

Let's run examples:

```bash
make basic-example
```

```bash
make ml-example
```

If it run successffully, spark submit command should outline something like this:
```
2018-05-27 14:00:16 INFO  LoggingPodStatusWatcherImpl:54 - State changed, new state:
	 pod name: spark-pi-63ba1a53bc663d728936c24c91fb339b-driver
	 namespace: default
	 labels: spark-app-selector -> spark-2a6817ac76a248ba8a9cef7f3b988d82, spark-role -> driver
	 pod uid: 4698a7b8-61b6-11e8-b653-42010a840124
	 creation time: 2018-05-27T14:00:13Z
	 service account name: spark
	 volumes: spark-token-92jw7
	 node name: gke-spark-default-pool-ba0e670d-w989
	 start time: 2018-05-27T14:00:13Z
	 container images: hypnosapos/spark:2.3
	 phase: Succeeded
2018-05-27 14:00:16 INFO  LoggingPodStatusWatcherImpl:54 - Container final statuses:
Container name: spark-kubernetes-driver
	 Container image: hypnosapos/spark:2.3
	 Container state: Terminated
	 Exit code: 0
2018-05-27 14:00:16 INFO  Client:54 - Application spark-pi finished.
```

## TODO

- [ ] Check HDFS and data locality based on https://databricks.com/session/hdfs-on-kubernetes-lessons-learned