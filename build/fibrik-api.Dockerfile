# fibrik-api image. Build context: the repository root.
FROM python:3.12.15-slim AS build
WORKDIR /src
COPY pyproject.toml README.md ./
COPY fibrik ./fibrik
RUN pip install --no-cache-dir --prefix=/install .

FROM python:3.12.15-slim
COPY --from=build /install /usr/local
RUN useradd --uid 10001 --no-create-home fibrik
USER 10001
EXPOSE 8000
ENTRYPOINT ["fibrik"]
CMD ["serve"]
