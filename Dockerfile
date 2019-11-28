ARG MVN_VERSION='3.5.4'
ARG JDK_VERSION='8'

FROM maven:${MVN_VERSION}-jdk-${JDK_VERSION}-slim

ARG GIT_SPARK='v2.4.4'

RUN apt update && apt install git docker python --yes

RUN git clone git://github.com/apache/spark.git

WORKDIR spark

RUN git checkout ${GIT_SPARK}

RUN curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh

RUN mvn -Pkubernetes -DskipTests clean package

CMD bash
