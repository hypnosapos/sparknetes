.PHONY: help build-builder pub-builder download-builder build-pub basic-example
.DEFAULT_GOAL := help

DOCKER_MVN_VERSION ?= 3.5.3
DOCKER_JDK_VERSION ?= 8
DOCKER_GIT_SPARK   ?= branch-2.3
DOCKER_ORG         ?= hypnosapos
DOCKER_IMAGE       ?= sparknetes
DOCKER_TAG         ?= 2.3
KUBE_API           ?= http://127.0.0.1:8001

help: ## Show this help
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

clean:
	@docker rm -f $$(docker ps -a -f "ancestor=$(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)" --format '{{.Names}}') > /dev/null 2>&1 || echo "No containers for ancestor $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)"
	@docker rm -f $$(docker ps -a -f "ancestor=$(DOCKER_ORG)/spark:$(DOCKER_TAG)" --format '{{.Names}}') > /dev/null 2>&1 || echo "No containers for ancestor $(DOCKER_ORG)/spark:$(DOCKER_TAG)"
	@docker rmi -f $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) > /dev/null 2>&1 || echo "No images of $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)"
	@docker rmi -f $(DOCKER_ORG)/spark:$(DOCKER_TAG) > /dev/null 2>&1 || echo "No images of $(DOCKER_ORG)/spark:$(DOCKER_TAG)"

build-builder: ## Build the docker image of builder
	@docker build --build-arg MVN_VERSION=$(DOCKER_MVN_VERSION)\
	  --build-arg JDK_VERSION=$(DOCKER_JDK_VERSION)\
	  --build-arg GIT_SPARK=$(DOCKER_GIT_SPARK)\
	  -t $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) .

pub-builder: ## Push docker image of sparknetes builder
	@docker login && docker push $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)

download-builder: ## Download a pre-built builder
	@docker pull $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)

build-pub: download-builder ## Build and push a docker image for spark to be used on kubernetes deployment
	docker run -it --rm\
	   -v /var/run/docker.sock:/var/run/docker.sock\
	   $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)\
	   bash -c "docker login\
                && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) build\
                && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) push"

check-kube: ## Setup kubernetes cluster
	kubectl proxy &
	kubectl create serviceaccount spark
	kubectl create clusterrolebinding spark-role --clusterrole=edit --serviceaccount=default:spark --namespace=default

basic-example: ## Launch basic example
	@docker run -it --network host\
	   $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)\
	   bash -c "./bin/spark-submit\
                --master k8s://$(KUBE_API)\
                --deploy-mode cluster\
                --name spark-pi\
                --class org.apache.spark.examples.SparkPi\
                --conf spark.executor.instances=3\
                --conf spark.kubernetes.container.image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) \
                --conf spark.kubernetes.authenticate.driver.serviceAccountName=spark \
    	        local:///opt/spark/examples/target/original-spark-examples_2.11-2.3.2-SNAPSHOT.jar"