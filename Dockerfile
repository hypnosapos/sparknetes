ARG MVN_VERSION='3.5.3'
ARG JDK_VERSION='8'

FROM maven:${MVN_VERSION}-jdk-${JDK_VERSION}-slim

ARG GIT_SPARK='branch-2.3'

RUN apt update && apt install git docker python --yes

RUN git clone -b ${GIT_SPARK} git://github.com/apache/spark.git

WORKDIR spark

RUN curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh

RUN mvn -Pkubernetes -DskipTests clean package

CMD bash
