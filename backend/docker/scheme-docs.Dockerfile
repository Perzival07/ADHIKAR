# Data image: the scheme documents folder, versioned like code.
# Eligibility and ingestion pods copy /docs into a shared volume with an init container, so updating the
# knowledge base is "build a new docs image tag + roll out", with no PVCs to edit by hand.
FROM busybox:1.36
COPY data/scheme_docs /docs
USER 65534:65534
CMD ["sh", "-c", "cp -r /docs/. /target/ && echo copied $(ls /target | wc -l) files"]
