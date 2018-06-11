# Sparknetes
[![Build status](https://circleci.com/gh/hypnosapos/sparknetes/tree/master.svg?style=svg "Build status")](https://circleci.com/gh/hypnosapos/sparknetes/tree/master)
[![sparknetes layers](https://images.microbadger.com/badges/image/hypnosapos/sparknetes.svg "sparknetes layers")](https://microbadger.com/images/hypnosapos/sparknetes)
[![sparknetes version](https://images.microbadger.com/badges/version/hypnosapos/sparknetes.svg "sparknetes version")](https://microbadger.com/images/hypnosapos/sparknetes)
[![spark layers](https://images.microbadger.com/badges/image/hypnosapos/spark.svg "spark layers")](https://microbadger.com/images/hypnosapos/spark)
[![spark version](https://images.microbadger.com/badges/version/hypnosapos/spark.svg "spark version")](https://microbadger.com/images/hypnosapos/spark)

Spark on kubernetes. Based on official documentation of spark 2.3 at https://spark.apache.org/docs/2.3.0/running-on-kubernetes.html

## Requirerements:

- Docker.
- Kubernetes 1.8+ (examples were tested on GKE service).

## Spark docker images

In order to get base docker images to use with `spark-submit` command we may use this intermediate docker image:

```sh
make sparknetes-build spark-images
```
> NOTE: This process may take you several minutes (~20 mins, under the wood there is a maven packaging task running).
 Take a look at Makefile file to view default values and other variables.

We've left docker images available under the dockerhub org [dockerhub/hypnosapos](https://hub.docker.com/r/hypnosapos/) (sparknetes and spark images)

You could push your own images as well by:
```sh
DOCKER_ORG=<registry_org> DOCKER_USERNAME=<registry_user> DOCKER_PASSWORD=<registry_pass> make sparknetes-build spark-images
```

## Kubernetes cluster

We've tried examples on GKE service. This is the command to get up a kubernetes cluster, ready to be used for spark deployments:

```sh
export GCP_CREDENTIALS=<path_file_gcp.json>
export GCP_ZONE=<gcp_zone>
export GCP_PROJECT_ID=<gcp_project_id>
export GKE_CLUSTER_NAME=spark

make gke-bastion gke-create-cluster gke-spark-bootstrap gke-proxy
```

If you prefer to use another cluster on other cloud or infrastructure (even local station), it's up to you.

For those people who want to use the kubernetes dashboard:

```sh
make gke-ui-login-skip gke-ui
```
> NOTE: `gke-ui-login-skip` is a trick to add cluster admin credentials to default dashboard account (skipping login page)

## Launch basic examples

![Spark on kubernetes](sparknetes_basic.png)

As the picture above show you, `spark-submit` commands will be thrown from a pod of a kubernetes job.

First example is the well known SparkPi:
```sh
make spark-basic-example
```

Second one is an example of a linear regresion:
```sh
make spark-ml-example
```

Logs of job that run spark-submit command was launched can be seen on this way:

```sh
JOB_NAME=<job_name> make gke-job-logs
```
> NOTE: <job-name> is the name of the example with the suffix '-job' instead of '-example' (i.e. "spark-ml-job" instead of "spark-ml-example")

If it run successffully, spark-submit command should outline something like this:
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

## GCS example

![GCS and Spark on kubernetes](sparknetes_gcs.png)

This example uses a remote dependency for gcs connector and the GCP credentials to authenticate with internal metadata server.
We've used a private jar and class (provide your values directly in Makefile file), but essentially you only need update your code to use `gs://` instead the typical `hdfs://` scheme for data input/output.

```sh
make example-gcs
```

## Cleaning

### Remove all spark resources on kubernetes cluster

```sh
make gke-spark-clean
```

### Remove everything

```sh
make gke-destroy-cluster
```

## TODO
- [ ] Benchmarks.
- [ ] Check HDFS and data locality based on https://databricks.com/session/hdfs-on-kubernetes-lessons-learned.
- [ ] BigDL examples, update to Spark 2.3.