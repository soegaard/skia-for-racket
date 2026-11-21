# Stage A audit and natipkg qualification. Acquire first; execute with --network none.
# Record the resulting image digest and dpkg inventory. apt packages are not a
# frozen release image, and this does not qualify a glibc 2.27 baseline.
FROM debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc
RUN apt-get update && apt-get install -y --no-install-recommends python3 binutils ca-certificates libglib2.0-0 && rm -rf /var/lib/apt/lists/*
