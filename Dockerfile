# The `fibrik` Python control-plane image (initial-stack.md §4/§6: Python
# 3.12, multi-arch, GHCR). Right now this only needs to run `fibrik lake
# write` (deploy/helm/fibrik/templates/lake-writer.yaml) -- the CLI's other
# subcommands (api, agents, mcp_servers, ...) don't exist yet (later phases),
# but there's no reason for this image to change shape when they land, only
# pyproject.toml's dependency list to grow.
#
# Not built/pushed to GHCR by CI yet -- `make kind-load` builds it locally
# and loads it straight into the kind cluster for `make ci-kind`, the same
# way a Mac mini/k3d dev loop would. Publishing a real multi-arch GHCR image
# with cosign signing (initial-stack.md §6) is a follow-up once this image
# is doing more than one CLI command.
FROM python:3.12-slim AS build

WORKDIR /app
COPY pyproject.toml README.md ./
COPY fibrik ./fibrik
RUN pip install --no-cache-dir --root-user-action=ignore .

FROM python:3.12-slim

RUN useradd --no-create-home --uid 10001 fibrik
COPY --from=build /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=build /usr/local/bin/fibrik /usr/local/bin/fibrik

USER fibrik
ENTRYPOINT ["fibrik"]
