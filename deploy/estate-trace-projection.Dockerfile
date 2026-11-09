# Forward packaging repair over the exact deployed image; no provider/kernel rebuild.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
USER root
COPY unbundle-estate-capability.py /tmp/unbundle-estate-capability.py
COPY project-trace-encoder.py /tmp/project-trace-encoder.py
RUN python3 /tmp/unbundle-estate-capability.py --root /opt/sfx append-api-run-trace \
    && python3 /tmp/project-trace-encoder.py --root /opt/sfx \
    && rm /tmp/unbundle-estate-capability.py /tmp/project-trace-encoder.py
