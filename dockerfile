FROM ubuntu:focal as base
RUN apt-get update

ENV TIKA_VERSION 2.6.0
ENV TIKA_SERVER_JAR tika-server-standard

FROM base as dependencies

RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -y install gdal-bin tesseract-ocr \
        tesseract-ocr-eng curl gnupg

# Set this environment variable if you need to run OCR
ENV OMP_THREAD_LIMIT=1

RUN echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y xfonts-utils fonts-freefont-ttf fonts-liberation ttf-mscorefonts-installer wget cabextract

RUN wget -O adoptium-public.key https://packages.adoptium.net/artifactory/api/gpg/key/public && \
    apt-key add adoptium-public.key && \
    echo "deb https://packages.adoptium.net/artifactory/deb $(awk -F= '/^VERSION_CODENAME/{print$2}' /etc/os-release) main" > /etc/apt/sources.list.d/adoptium.list && \ 
    apt-get update && apt-get -y install temurin-17-jdk


FROM dependencies as fetch_tika

ENV NEAREST_TIKA_SERVER_URL="https://www.apache.org/dyn/closer.cgi/tika/${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar?filename=tika/${TIKA_VERSION}/${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar&action=download" \
    ARCHIVE_TIKA_SERVER_URL="https://archive.apache.org/dist/tika/${TIKA_VERSION}/${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar" \
    DEFAULT_TIKA_SERVER_ASC_URL="https://downloads.apache.org/tika/${TIKA_VERSION}/${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar.asc" \
    ARCHIVE_TIKA_SERVER_ASC_URL="https://archive.apache.org/dist/tika/${TIKA_VERSION}/${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar.asc" \
    TIKA_VERSION=$TIKA_VERSION

RUN DEBIAN_FRONTEND=noninteractive apt-get -y install gnupg2 \
    && wget -t 10 --max-redirect 1 --retry-connrefused -qO- https://downloads.apache.org/tika/KEYS | gpg --import \
    && wget -t 10 --max-redirect 1 --retry-connrefused $NEAREST_TIKA_SERVER_URL -O /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar || rm /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar \
    && sh -c "[ -f /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar ]" || wget $ARCHIVE_TIKA_SERVER_URL -O /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar || rm /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar \
    && sh -c "[ -f /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar ]" || exit 1 \
    && wget -t 10 --max-redirect 1 --retry-connrefused $DEFAULT_TIKA_SERVER_ASC_URL -O /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar.asc  || rm /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar.asc \
    && sh -c "[ -f /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar.asc ]" || wget $ARCHIVE_TIKA_SERVER_ASC_URL -O /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar.asc || rm /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar.asc \
    && sh -c "[ -f /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar.asc ]" || exit 1 \
    && gpg --verify /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar.asc /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar

# This is where we get the extra dependencies
RUN wget -t 10 --max-redirect 1 --retry-connrefused https://repo1.maven.org/maven2/org/apache/tika/tika-fetcher-s3/${TIKA_VERSION}/tika-fetcher-s3-${TIKA_VERSION}.jar -O /tika-fetcher-s3-${TIKA_VERSION}.jar \
    && wget -t 10 --max-redirect 1 --retry-connrefused https://repo1.maven.org/maven2/org/apache/tika/tika-fetcher-s3/${TIKA_VERSION}/tika-fetcher-s3-${TIKA_VERSION}.jar.asc -O /tika-fetcher-s3-${TIKA_VERSION}.jar.asc \
    && gpg --verify /tika-fetcher-s3-${TIKA_VERSION}.jar.asc /tika-fetcher-s3-${TIKA_VERSION}.jar \
    && wget -t 10 --max-redirect 1 --retry-connrefused https://repo1.maven.org/maven2/org/apache/tika/tika-emitter-s3/${TIKA_VERSION}/tika-emitter-s3-${TIKA_VERSION}.jar -O /tika-emitter-s3-${TIKA_VERSION}.jar \
    && wget -t 10 --max-redirect 1 --retry-connrefused https://repo1.maven.org/maven2/org/apache/tika/tika-emitter-s3/${TIKA_VERSION}/tika-emitter-s3-${TIKA_VERSION}.jar.asc -O /tika-emitter-s3-${TIKA_VERSION}.jar.asc \
    && gpg --verify /tika-emitter-s3-${TIKA_VERSION}.jar.asc /tika-emitter-s3-${TIKA_VERSION}.jar

FROM dependencies as runtime
RUN apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
ENV TIKA_VERSION=$TIKA_VERSION
RUN mkdir /tika-bin
COPY --from=fetch_tika /${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar /tika-bin/${TIKA_SERVER_JAR}-${TIKA_VERSION}.jar
# The extra dependencies need to be added into tika-bin together with the tika-server jar
COPY --from=fetch_tika /tika-fetcher-s3-${TIKA_VERSION}.jar /tika-bin/tika-fetcher-s3-${TIKA_VERSION}.jar
COPY --from=fetch_tika /tika-emitter-s3-${TIKA_VERSION}.jar /tika-bin/tika-emitter-s3-${TIKA_VERSION}.jar

EXPOSE 9998
ENTRYPOINT [ "/bin/sh", "-c", "exec java -cp \"/tika-bin/*\" org.apache.tika.server.core.TikaServerCli -h 0.0.0.0 $0 $@"]