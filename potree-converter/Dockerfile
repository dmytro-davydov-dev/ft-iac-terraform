# Stage 1: Build PotreeConverter from source
FROM debian:12-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    libtbb-dev \
  && rm -rf /var/lib/apt/lists/*

ARG POTREECONVERTER_VERSION=2.1.1
RUN git clone --depth 1 --branch ${POTREECONVERTER_VERSION} \
      https://github.com/potree/PotreeConverter.git /src \
  && cmake -S /src -B /src/build -DCMAKE_BUILD_TYPE=Release \
  && cmake --build /src/build --target PotreeConverter -j$(nproc) \
  && install -m 755 /src/build/PotreeConverter /usr/local/bin/PotreeConverter

# Stage 2: Runtime image
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libtbb12 \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/bin/PotreeConverter /usr/local/bin/PotreeConverter

RUN pip install --no-cache-dir \
    google-cloud-storage==2.18.2 \
    httpx==0.27.0

WORKDIR /app
COPY convert.py .

ENTRYPOINT ["python", "convert.py"]
