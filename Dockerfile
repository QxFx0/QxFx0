FROM haskell:9.6.6-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    agda \
    agda-stdlib \
    gf \
    libsqlite3-dev \
    libz-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY qxfx0.cabal cabal.project ./
RUN cabal update && cabal configure --enable-optimization=2

COPY src/ src/
COPY app/ app/
COPY spec/ spec/

RUN agda spec/R5Core.agda && \
    agda spec/Sovereignty.agda && \
    agda spec/Legitimacy.agda && \
    agda spec/LexiconData.agda && \
    agda spec/LexiconProof.agda

RUN gf -make -f pgf spec/gf/QxFx0SyntaxRus.gf

RUN cabal build all --only-dependencies && \
    cabal build qxfx0-main

RUN mkdir -p /dist/bin && \
    cp $(cabal list-bin qxfx0-main) /dist/bin/qxfx0-main

FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    gf \
    libsqlite3-0 \
    libgmp10 \
    libffi8 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r qxfx0 && useradd -r -g qxfx0 -d /data -s /sbin/nologin qxfx0

COPY --from=builder /dist/bin/qxfx0-main /usr/local/bin/qxfx0-main
COPY scripts/http_runtime.py /usr/local/bin/http_runtime.py
COPY semantics/ /data/semantics/
COPY spec/sql/ /data/spec/sql/
COPY spec/sql/lexicon/ /data/spec/sql/lexicon/
COPY spec/datalog/ /data/spec/datalog/
COPY spec/gf/ /data/spec/gf/
COPY migrations/ /data/migrations/
COPY resources/ /data/resources/

RUN mkdir -p /data && chown -R qxfx0:qxfx0 /data

VOLUME ["/data"]

ENV QXFX0_ROOT=/data
ENV QXFX0_DB=/data/qxfx0.db
ENV QXFX0_HTTP_RUNTIME=/usr/local/bin/http_runtime.py
ENV QXFX0_HTTP_PORT=9170

EXPOSE 9170

USER qxfx0

ENTRYPOINT ["/usr/local/bin/qxfx0-main", "--serve-http"]
