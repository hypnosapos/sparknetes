# Sparknetes

Spark on kubernetes. Based on official site of spark 2.3 at https://spark.apache.org/docs/2.3.0/running-on-kubernetes.html

Tests were run over GKE service.

## Publish your docker images

In order to get base docker images to use with spark submit command we may use this intermediate docker container:

```bash
make build-pub
```
> NOTE: Take a look at Makefile file to view default values and other variables.

We've left a docker image available at [dockerhub/hypnosapos/spark](https://hub.docker.com/r/hypnosapos/spark/tags/)

## Launch examples

Before run examples you must provide a kuberntes cluster ready for use.

Til now we've try examples only over GKE service, once a cluster is ready run the "sparknetes proxy" on this way:

```bash
GCP_ZONE=<gcp_zone> \
GCP_PROJECT_ID=<gcp_project_id> \
GCP_CLUSTER_NAME=spark \
GCP_CLUSTER_ADMIN_PASS=******** \
GCP_CREDENTIALS=<path_file_gcp.json> \
GCP_CLUSTER_ADMIN_PASS=*********** \
make sparknetes-gke-proxy
```

This container will be use to launch examples through the internel proxy URL (http://127.0.0.1:8001)

Let's run a basic example:

```bash
make basic-example
```

If everything was well the output of the spark submit command should be like this:
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

- [ ] Check HDFS and data locallity based on https://databricks.com/session/hdfs-on-kubernetes-lessons-learned