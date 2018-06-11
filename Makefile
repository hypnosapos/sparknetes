.PHONY: help clean sparknetes-build sparknetes-push spark-images gke-bastion gke-create-cluster gke-destroy-cluster gke-spark-clean gke-spark-bootstrap gke-proxy gke-ui-login-skip gke-ui spark-basic-example spark-ml-example spark-gcs-example
.DEFAULT_GOAL := help

DOCKER_MVN_VERSION ?= 3.5.3
DOCKER_JDK_VERSION ?= 8
DOCKER_GIT_SPARK   ?= branch-2.3
DOCKER_ORG         ?= hypnosapos
DOCKER_IMAGE       ?= sparknetes
DOCKER_TAG         ?= 2.3
GCLOUD_IMAGE_TAG   ?= 203.0.0-alpine
GCP_CREDENTIALS    ?= $$HOME/gcp.json
GCP_ZONE           ?= my_zone
GCP_PROJECT_ID     ?= my_project
GKE_CLUSTER_NAME   ?= spark

UNAME := $(shell uname -s)
ifeq ($(UNAME),Linux)
OPEN := xdg-open
else
OPEN := open
endif


help: ## Show this help.
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

clean:
	@docker rm -f $$(docker ps -a -f "ancestor=$(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)" --format '{{.Names}}') > /dev/null 2>&1 || echo "No containers for ancestor $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)"
	@docker rmi -f $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) > /dev/null 2>&1 || echo "No images of $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)"

sparknetes-build: ## Build the docker image of builder.
	@docker build \
	  --build-arg MVN_VERSION=$(DOCKER_MVN_VERSION) \
	  --build-arg JDK_VERSION=$(DOCKER_JDK_VERSION) \
	  --build-arg GIT_SPARK=$(DOCKER_GIT_SPARK) \
	  -t $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) .

sparknetes-push: ## Publish sparknetes docker image.
	@docker push $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)

spark-image: ## Build and push a docker image for spark pods.
	@docker pull $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)
	@docker run -it --rm\
	   -v /var/run/docker.sock:/var/run/docker.sock\
	   $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) \
	   bash -c "docker login -u $$DOCKER_USERNAME -p $$DOCKER_PASSWORD \
	            && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) build\
	            && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) push"

gke-bastion: ## Run a gke-bastion container.
	@docker run -it -d --name gke-bastion \
	   -p 8001:8001 -p 4040:4040 \
	   -v $(GCP_CREDENTIALS):/tmp/gcp.json \
	   google/cloud-sdk:$(GCLOUD_IMAGE_TAG) \
	   sh
	@docker exec gke-bastion \
	   sh -c "gcloud components install kubectl --quiet \
	          && gcloud auth activate-service-account --key-file=/tmp/gcp.json"

gke-create-cluster: ## Create a kubernetes cluster on GKE.
	@docker exec gke-bastion \
	   sh -c "gcloud container --project $(GCP_PROJECT_ID) clusters create $(GKE_CLUSTER_NAME) --zone "$(GCP_ZONE)" \
	          --username "admin" --cluster-version "1.8.10-gke.0" --machine-type "n1-standard-4" --image-type "COS" \
	          --disk-type "pd-standard" --disk-size "100" \
	          --scopes "compute-rw","storage-rw","logging-write","monitoring","service-control","service-management","trace" \
	          --num-nodes "5" --enable-cloud-logging --enable-cloud-monitoring --network "default" \
	          --subnetwork "default" --addons HorizontalPodAutoscaling,HttpLoadBalancing,KubernetesDashboard \
	          && gcloud container clusters get-credentials $(GKE_CLUSTER_NAME) --zone "$(GCP_ZONE)" --project $(GCP_PROJECT_ID)"
	@docker exec gke-bastion \
	   sh -c "kubectl config set-credentials gke_$(GCP_PROJECT_ID)_$(GCP_ZONE)_$(GKE_CLUSTER_NAME) --username=admin \
	          --password=$$(gcloud container clusters describe $(GKE_CLUSTER_NAME) | grep password | awk '{print $$2}')"

gke-spark-bootstrap: ## Setup kubernetes cluster for spark examples.
	@docker exec gke-bastion \
	   sh -c "kubectl create serviceaccount $(GKE_CLUSTER_NAME) \
                 && kubectl create clusterrolebinding spark-role --clusterrole=edit --serviceaccount=default:$(GKE_CLUSTER_NAME) --namespace=default \
                 && kubectl create secret generic gcloud-creds --from-file=gcp.json=/tmp/gcp.json"

gke-ui-login-skip: ## TRICK: Grant complete access to dashboard. Be careful, anyone could enter into your dashboard and execute admin ops.
	@docker cp $(shell pwd)/skip_login.yml gke-bastion:/tmp/skip_login.yml
	@docker exec gke-bastion \
	  sh -c "kubectl create -f /tmp/skip_login.yml"

gke-proxy: ## Run kubectl proxy on sparknetes container.
	@docker exec -it gke-bastion \
	   sh -c "kubectl proxy --address='0.0.0.0'"

gke-ui: ## Launch kubernetes dashboard through the proxy.
	$(OPEN) http://127.0.0.1:8001/ui

gke-spark-clean: ## Clean spark resources on kubernetes cluster.
	@docker exec gke-bastion \
	  sh -c "kubectl delete all -l sparknetes=true"

gke-destroy-cluster: ## Remove kubernetes cluster.
	@docker exec gke-bastion \
	  sh -c "gcloud container --project $(GCP_PROJECT_ID) clusters delete $(GKE_CLUSTER_NAME) --zone=$(GCP_ZONE) --quiet"

gke-job-logs: ## Follow logs of jobs. JOB_NAME variable is required.
	@docker exec -it gke-bastion \
	  sh -c "kubectl logs -f $$(kubectl get pods -l job-name=$(JOB_NAME) -o jsonpath={.items..metadata.name})"

spark-basic-example: ## Launch basic example (SparkPi) from a kubernetes pod.
	@docker exec gke-bastion \
	  sh -c "kubectl run spark-basic-job -l sparknetes=true --image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) --restart=OnFailure \
	       --serviceaccount=spark --command -- /opt/spark/bin/spark-submit \
	       --master k8s://https://kubernetes.default.svc.cluster.local \
	       --deploy-mode cluster \
	       --name spark-basic-pi \
	       --class org.apache.spark.examples.SparkPi \
	       --conf spark.executor.instances=3 \
	       --conf spark.kubernetes.container.image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) \
	       --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
	       --conf spark.kubernetes.driver.label.sparknetes=true \
	       local:///opt/spark/examples/target/original-spark-examples_2.11-2.3.2-SNAPSHOT.jar"

spark-ml-example: ## Launch ml example from a kubernetes pod.
	@docker exec gke-bastion \
	  sh -c "kubectl run spark-ml-job -l sparknetes=true --image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) --restart=OnFailure \
	       --serviceaccount=spark --command -- /opt/spark/bin/spark-submit \
	       --master k8s://https://kubernetes.default.svc.cluster.local \
	       --deploy-mode cluster \
	       --name spark-ml-LR \
	       --class org.apache.spark.examples.SparkLR \
	       --conf spark.executor.instances=3 \
	       --conf spark.kubernetes.container.image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) \
	       --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
	       --conf spark.kubernetes.driver.label.sparknetes=true \
	       local:///opt/spark/examples/target/original-spark-examples_2.11-2.3.2-SNAPSHOT.jar"

spark-gcs-example: ## Launch an example with GCS as data source. Adjust class and other confs
	@docker exec gke-bastion \
	sh -c "kubectl run spark-gcs-job -l sparknetes=true --image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) --restart=OnFailure \
	       --serviceaccount=spark --command -- /opt/spark/bin/spark-submit \
	       --master k8s://https://kubernetes.default.svc.cluster.local \
	       --deploy-mode cluster \
	       --name spark-gcs \
	       --class <your_class> \
	       --conf spark.executor.instances=4 \
	       --jars https://storage.googleapis.com/sparknetes/libs/gcs-connector-1.6.6-hadoop2.jar \
	       --conf spark.kubernetes.container.image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) \
	       --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
	       --conf spark.kubernetes.driverEnv.GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp/gcp.json \
	       --conf spark.executor.memory=4g \
	       --conf spark.kubernetes.executor.limit.cores=3 \
	       --conf spark.executor.cores=3 \
	       --conf spark.kubernetes.driver.secrets.gcloud-creds=/tmp/gcp \
	       --conf spark.kubernetes.driver.label.sparknetes=true \
	       <your_remote_jar> gs://<input_bucket> gs://<output_bucket>"

# hdfs-example: ## Example with HDSF as data source
# TODO: https://databricks.com/session/hdfs-on-kubernetes-lessons-learned
