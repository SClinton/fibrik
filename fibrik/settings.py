"""Runtime settings, read from FIBRIK_* environment variables.

The Helm chart sets these; nothing here names a cloud provider. The storage
fields are the "storage profile" (Option A): one description of the object
store that every component turns into its own native client settings.
"""

from functools import lru_cache
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class StorageSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="FIBRIK_STORAGE_")

    type: Literal["s3"] = "s3"
    bucket: str = "fibrik-lake"
    # Empty means the provider default (AWS). Set for S3-compatible stores
    # (SeaweedFS, R2, OCI, Ceph, MinIO).
    endpoint: str = ""
    region: str = "us-east-1"
    path_style: bool = True
    access_key_id: str = ""
    secret_access_key: str = ""
    # Vector writes newline-delimited JSON batches here; the lake writer
    # commits them to Iceberg and moves them to the archive prefix.
    pending_prefix: str = "raw/pending/"
    archive_prefix: str = "raw/archive/"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="FIBRIK_")

    clickhouse_url: str = "http://localhost:8123"
    clickhouse_user: str = "fibrik"
    clickhouse_password: str = ""
    clickhouse_database: str = "fibrik"
    hot_ttl_days: int = 7

    # Iceberg catalog. "rest" is Lakekeeper (any Iceberg REST catalog works);
    # "sql" is a local SQLite catalog for tests (catalog_uri is then a
    # SQLAlchemy URL such as sqlite:////tmp/catalog.db).
    catalog_type: Literal["rest", "sql"] = "rest"
    catalog_uri: str = "http://localhost:8181/catalog"
    catalog_management_uri: str = "http://localhost:8181/management"
    warehouse: str = "fibrik"
    lake_namespace: str = "fibrik"
    lake_writer_enabled: bool = True
    lake_writer_interval_seconds: float = 10.0

    storage: StorageSettings = Field(default_factory=StorageSettings)


@lru_cache
def get_settings() -> Settings:
    return Settings()
