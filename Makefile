.PHONY: help clean sparknetes-build sparknetes-gke-build spark-images sparknetes-gke sparknetes-gke-bootstrap sparknetes-gke-proxy basic-example ml-example
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

sparkenetes-build: ## Build the docker image of builder
	@docker build \
	  --build-arg MVN_VERSION=$(DOCKER_MVN_VERSION) \
	  --build-arg JDK_VERSION=$(DOCKER_JDK_VERSION) \
	  --build-arg GIT_SPARK=$(DOCKER_GIT_SPARK) \
	  -t $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) .

sparknetes-gke-build: ## Build the docker image of builder with gke support
	@docker build \
	  --build-arg SPARKENETES_VERSION=$(DOCKER_TAG) \
	  -t $(DOCKER_ORG)/$(DOCKER_IMAGE)-gke:$(DOCKER_TAG) -f Dockerfile_gke .

spark-images: ## Build and push a docker image for spark to be used on kubernetes deployments
	@docker pull $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)
	@docker run -it --rm\
	   -v /var/run/docker.sock:/var/run/docker.sock\
	   $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)\
	   bash -c "docker login\
                && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) build\
                && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) push"

sparknetes-gke: ## Run a sparknetes container
	@docker run -t --rm --name $(DOCKER_IMAGE) \
	   -v $(GCP_CREDENTIALS):/tmp/gcp.json \
	   $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) \
	   bash
	@docker exec $(DOCKER_IMAGE) ./entry.sh

sparknetes-gke-bootstrap: ## Setup kubernetes cluster for spark examples
	@docker exec $(DOCKER_IMAGE) \
	   bash -c "kubectl create serviceaccount spark \
                kubectl create clusterrolebinding spark-role --clusterrole=edit --serviceaccount=default:spark --namespace=default"

sparknetes-gke-proxy: ## Run kubectl proxy on sparknetes container
	@docker exec -it $(DOCKER_IMAGE) \
	   bash -c "kubectl proxy"

basic-example: ## Launch basic example
	@docker exec $(DOCKER_IMAGE)\
	   bash -c "./bin/spark-submit\
                --master k8s://http://127.0.0.1:8001\
                --deploy-mode cluster\
                --name spark-pi\
                --class org.apache.spark.examples.SparkPi\
                --conf spark.executor.instances=5\
                --conf spark.kubernetes.container.image=$(DOCKER_ORG)/spark:$(DOCKER_TAG)\
                --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark\
    	        local:///opt/spark/examples/target/original-spark-examples_2.11-2.3.2-SNAPSHOT.jar"

ml-example: ## Launch ml example
	@docker exec $(DOCKER_IMAGE)\
	   bash -c "./bin/spark-submit\
                --master k8s://http://127.0.0.1:8001\
                --deploy-mode cluster\
                --name spark-ml-LR\
                --class org.apache.spark.examples.SparkLR\
                --conf spark.executor.instances=5\
                --conf spark.kubernetes.container.image=$(DOCKER_ORG)/spark:$(DOCKER_TAG)\
                --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark\
    	        local:///opt/spark/examples/target/original-spark-examples_2.11-2.3.2-SNAPSHOT.jar"

# hdfs-example: ## Example with HDSF as data source
# TODO: https://databricks.com/session/hdfs-on-kubernetes-lessons-learned