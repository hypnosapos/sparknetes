.PHONY: help clean sparknetes-build sparknetes-gke-build spark-images sparknetes-gke sparknetes-gke-bootstrap sparknetes-gke-proxy load_gcp_secret basic-example ml-example gcs-example
.DEFAULT_GOAL := help

DOCKER_MVN_VERSION ?= 3.5.3
DOCKER_JDK_VERSION ?= 8
DOCKER_GIT_SPARK   ?= branch-2.3
DOCKER_ORG         ?= hypnosapos
DOCKER_IMAGE       ?= sparknetes
DOCKER_TAG         ?= 2.3
GCP_CREDENTIALS    ?= $$HOME/gcp.json
GCP_ZONE           ?= europe-west1-b
GCP_PROJECT_ID     ?= my_project
GCP_CLUSTER_NAME       ?= spark
GCP_CLUSTER_ADMIN_PASS ?= admin

help: ## Show this help
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

clean:
	@docker rm -f $$(docker ps -a -f "ancestor=$(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)" --format '{{.Names}}') > /dev/null 2>&1 || echo "No containers for ancestor $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)"
	@docker rm -f $$(docker ps -a -f "ancestor=$(DOCKER_ORG)/$(DOCKER_IMAGE)-gke:$(DOCKER_TAG)" --format '{{.Names}}') > /dev/null 2>&1 || echo "No containers for ancestor $(DOCKER_ORG)/$(DOCKER_IMAGE)-gke:$(DOCKER_TAG)"
	@docker rmi -f $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) > /dev/null 2>&1 || echo "No images of $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)"
	@docker rmi -f $(DOCKER_ORG)/$(DOCKER_IMAGE)-gke:$(DOCKER_TAG) > /dev/null 2>&1 || echo "No images of $(DOCKER_ORG)/$(DOCKER_IMAGE)-gke:$(DOCKER_TAG)"

sparknetes-build: ## Build the docker image of builder
	@docker build \
	  --build-arg MVN_VERSION=$(DOCKER_MVN_VERSION) \
	  --build-arg JDK_VERSION=$(DOCKER_JDK_VERSION) \
	  --build-arg GIT_SPARK=$(DOCKER_GIT_SPARK) \
	  -t $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) .

sparknetes-push: ## Publish sparknetes docker image
	@docker push $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)

sparknetes-gke-build: ## Build the docker image of builder with gke support
	@docker build \
	  --build-arg SPARKNETES_VERSION=$(DOCKER_TAG) \
	  -t $(DOCKER_ORG)/$(DOCKER_IMAGE)-gke:$(DOCKER_TAG) -f Dockerfile_gke .

sparknetes-gke-push: ## Publish sparknetes-gke docker image
	@docker push $(DOCKER_ORG)/$(DOCKER_IMAGE)-gke:$(DOCKER_TAG)

spark-images: ## Build and push a docker image for spark to be used on kubernetes deployments
	@docker pull $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)
	@docker run -it --rm\
	   -v /var/run/docker.sock:/var/run/docker.sock\
	   $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) \
	   bash -c "docker login -u $$DOCKER_USERNAME -p $$DOCKER_PASSWORD \
                && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) build\
                && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) push"

sparknetes-gke: ## Run a sparknetes container
	@docker run -it -d --name $(DOCKER_IMAGE)-gke \
	   -p 8001:8001 \
	   -v $(GCP_CREDENTIALS):/tmp/gcp.json \
	   -e GCP_CREDS_FILE=/tmp/gcp.json \
	   -e GCP_ZONE=$(GCP_ZONE) \
	   -e GCP_PROJECT_ID=$(GCP_PROJECT_ID) \
	   -e GCP_CLUSTER_NAME=$(GCP_CLUSTER_NAME) \
	   -e GCP_CLUSTER_ADMIN_PASS=$(GCP_CLUSTER_ADMIN_PASS) \
	   $(DOCKER_ORG)/$(DOCKER_IMAGE)-gke:$(DOCKER_TAG) \
	   bash
	@docker exec $(DOCKER_IMAGE)-gke bash -l -c "./entry.sh"

sparknetes-gke-bootstrap: ## Setup kubernetes cluster for spark examples
	@docker exec $(DOCKER_IMAGE)-gke \
	   bash -l -c "kubectl create serviceaccount spark \
                  && kubectl create clusterrolebinding spark-role --clusterrole=edit --serviceaccount=default:spark --namespace=default"

sparknetes-gke-proxy: ## Run kubectl proxy on sparknetes container
	@docker exec -it $(DOCKER_IMAGE)-gke \
	   bash -l -c "kubectl proxy --address='0.0.0.0'"

sparknetes-gke-clean: ## Clean sparknetes examples
	@docker exec $(DOCKER_IMAGE)-gke \
	  bash -l -c "kubectl delete all -l sparknetes=true"

load_gcp_secret:
	@docker exec $(DOCKER_IMAGE)-gke \
       bash -l -c "kubectl create secret generic gcloud-creds --from-file=gcp.json=/tmp/gcp.json"

basic-example: ## Launch basic example
	@docker exec $(DOCKER_IMAGE)-gke \
	   bash -l -c "./bin/spark-submit \
                  --master k8s://http://127.0.0.1:8001 \
                  --deploy-mode cluster \
                  --name spark-pi \
                  --class org.apache.spark.examples.SparkPi \
                  --conf spark.executor.instances=3 \
                  --conf spark.kubernetes.container.image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) \
                  --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
                  --conf spark.kubernetes.driver.label.sparknetes=true \
    	          local:///opt/spark/examples/target/original-spark-examples_2.11-2.3.2-SNAPSHOT.jar"

ml-example: ## Launch ml example
	@docker exec $(DOCKER_IMAGE)-gke \
	   bash -l -c "./bin/spark-submit \
                  --master k8s://http://127.0.0.1:8001 \
                  --deploy-mode cluster \
                  --name spark-ml-LR \
                  --class org.apache.spark.examples.SparkLR \
                  --conf spark.executor.instances=3 \
                  --conf spark.kubernetes.container.image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) \
                  --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
                  --conf spark.kubernetes.driver.label.sparknetes=true \
    	          local:///opt/spark/examples/target/original-spark-examples_2.11-2.3.2-SNAPSHOT.jar"

gcs-example: ## Launch an example using GCS as data source
	@docker exec $(DOCKER_IMAGE)-gke \
	   bash -l -c "./bin/spark-submit \
                  --master k8s://http://127.0.0.1:8001 \
                  --deploy-mode cluster \
                  --name spark-test-set \
                  --class <your_class> \
                  --conf spark.executor.instances=5 \
                  --jars https://storage.googleapis.com/sparknetes/libs/gcs-connector-1.6.6-hadoop2.jar \
                  --conf spark.kubernetes.container.image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) \
                  --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
                  --conf spark.kubernetes.driverEnv.GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp/gcp.json \
                  --conf spark.executor.memory=4g \
                  --conf spark.kubernetes.executor.limit.cores=3 \
                  --conf spark.executor.cores=3 \
                  --conf spark.kubernetes.driver.secrets.gcloud-creds=/tmp/gcp \
                  --conf spark.kubernetes.driver.label.sparknetes=true \
    	          https://storage.googleapis.com/sparknetes/<yourremote-jar> gs://<your_bucket>"


# hdfs-example: ## Example with HDSF as data source
# TODO: https://databricks.com/session/hdfs-on-kubernetes-lessons-learned