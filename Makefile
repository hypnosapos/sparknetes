.DEFAULT_GOAL := help

DOCKER_MVN_VERSION ?= 3.5.3
DOCKER_JDK_VERSION ?= 8
DOCKER_GIT_SPARK   ?= branch-2.3
DOCKER_ORG         ?= hypnosapos
DOCKER_IMAGE       ?= sparknetes
DOCKER_TAG         ?= 2.3

UNAME := $(shell uname -s)
ifeq ($(UNAME),Linux)
OPEN := xdg-open
else
OPEN := open
endif

.PHONY: help
help: ## Show this help.
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: clean
clean:
	@docker rm -f $$(docker ps -a -f "ancestor=$(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)" --format '{{.Names}}') > /dev/null 2>&1 || true
	@docker rmi -f $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) > /dev/null 2>&1 || true

.PHONY: sparknetes-build
sparknetes-build: ## Build the docker image of builder.
	@docker build \
	  --build-arg MVN_VERSION=$(DOCKER_MVN_VERSION) \
	  --build-arg JDK_VERSION=$(DOCKER_JDK_VERSION) \
	  --build-arg GIT_SPARK=$(DOCKER_GIT_SPARK) \
	  -t $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) .

.PHONY: sparknetes-push
sparknetes-push: ## Publish sparknetes docker image.
	@docker push $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)

.PHONY: spark-image
spark-image: ## Build and push a docker image for spark pods.
	@docker pull $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG)
	@docker run -it --rm\
	   -v /var/run/docker.sock:/var/run/docker.sock\
	   $(DOCKER_ORG)/$(DOCKER_IMAGE):$(DOCKER_TAG) \
	   bash -c "docker login -u $$DOCKER_USERNAME -p $$DOCKER_PASSWORD \
	            && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) build\
	            && ./bin/docker-image-tool.sh -r docker.io/$(DOCKER_ORG) -t $(DOCKER_TAG) push"

.PHONY: gke-spark-bootstrap
gke-spark-bootstrap: ## Setup kubernetes cluster for spark examples.
	@docker exec gke-bastion \
	   sh -c "kubectl create serviceaccount $(GKE_CLUSTER_NAME) \
                 && kubectl create clusterrolebinding spark-role --clusterrole=edit --serviceaccount=default:$(GKE_CLUSTER_NAME) --namespace=default \
                 && kubectl create secret generic gcloud-creds --from-file=gcp.json=/tmp/gcp.json"

.PHONY: gke-spark-clean
gke-spark-clean: ## Clean spark resources on kubernetes cluster.
	@docker exec gke-bastion \
	  sh -c "kubectl delete all -l sparknetes=true"

.PHONY: gke-job-logs
gke-job-logs: ## Follow logs of jobs. JOB_NAME variable is required.
	@docker exec -t gke-bastion \
	  sh -c "kubectl logs -f job/$(JOB_NAME)"

.PHONY: spark-basic-example
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

.PHONY: spark-ml-example
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

.PHONY: spark-gcs-example
spark-gcs-example: ## Launch an example with GCS as data source. Adjust class and other confs
	@docker exec gke-bastion \
	  sh -c "kubectl run spark-gcs-job -l sparknetes=true --image=$(DOCKER_ORG)/spark:$(DOCKER_TAG) --restart=OnFailure \
	       --serviceaccount=spark --command -- /opt/spark/bin/spark-submit \
	       --master k8s://https://kubernetes.default.svc.cluster.local \
	       --deploy-mode cluster \
	       --name spark-gcs \
	       --class <your_class> \
	       --conf spark.executor.instances=4 \
	       --conf spark.ui.enabled=true \
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

.PHONY: gke-spark-expose-ui
gke-spark-expose-ui:
	@SPARK_PODS=`docker exec gke-bastion \
	  sh -c "kubectl get pods --show-all -l spark-role=driver -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.metadata.annotations.spark-app-name}{\"\\n\"}{end}'"`; \
	SPARK_POD=`echo $$SPARK_PODS | grep $(SPARK_APP_NAME) | awk '{print $$1}'`; \
	docker exec gke-bastion \
	  sh -c "kubectl expose pod $$SPARK_POD --name $(SPARK_APP_NAME)-svc --port=4040 --target-port=4040 --type=LoadBalancer"
	## Use pod port-forward or proxy url for an internal service

.PHONY: gke-spark-open-ui
gke-spark-open-ui:
	$(OPEN) http://$(shell docker exec gke-bastion \
	  sh -c "kubectl get svc $(SPARK_APP_NAME)-svc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"):4040

# hdfs-example: ## Example with HDSF as data source
# TODO: https://databricks.com/session/hdfs-on-kubernetes-lessons-learned
