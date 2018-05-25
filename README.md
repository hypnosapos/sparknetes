# Sparknetes

Spark on kubernetes

## Publish your docker images

In order to get base docker images to use with spark submit command we may use this intermediate docker container:

```sh
make build-pub
```

We've left a docker image available at [dockerhub/hypnosapos/spark](https://hub.docker.com/r/hypnosapos/spark/tags/)

## Launch examples

Just type:

```sh
make basic-example
```