"""Iceberg catalog access (Lakekeeper over the Iceberg REST API)."""

import logging

import httpx
from pyiceberg.catalog import Catalog, load_catalog
from pyiceberg.catalog.rest import RestCatalog
from pyiceberg.exceptions import NamespaceAlreadyExistsError
from pyiceberg.io import FileIO
from pyiceberg.table import Table

from fibrik.lake.schema import ICEBERG_SCHEMA, PARTITION_SPEC, RAW_LOGS
from fibrik.settings import Settings

log = logging.getLogger(__name__)


def _io_properties(s: Settings) -> dict[str, str]:
    # Fibrik reads and writes data files with its own storage credentials,
    # so the catalog does not need to vend credentials (R2 and SeaweedFS
    # have no STS).
    st = s.storage
    props = {
        "s3.region": st.region,
        "s3.force-virtual-addressing": str(not st.path_style).lower(),
    }
    if st.endpoint:
        props["s3.endpoint"] = st.endpoint
    if st.access_key_id:
        props["s3.access-key-id"] = st.access_key_id
        props["s3.secret-access-key"] = st.secret_access_key
    return props


# Table-config keys a REST catalog may send to choose how clients reach
# storage (remote signing, vended credentials). Fibrik ignores them.
_SERVER_IO_KEYS = (
    "py-io-impl",
    "s3.remote-signing-enabled",
    "s3.signer",
    "s3.access-key-id",
    "s3.secret-access-key",
    "s3.session-token",
    "s3.endpoint",
    "s3.region",
)


def own_io_properties(server: dict[str, str], own: dict[str, str]) -> dict[str, str]:
    """Merge table config from the catalog with Fibrik's storage profile, ours winning."""
    kept = {k: v for k, v in server.items() if not k.startswith(_SERVER_IO_KEYS)}
    return kept | own


class FibrikRestCatalog(RestCatalog):
    """REST catalog whose tables always use Fibrik's own storage credentials.

    Lakekeeper answers with remote-signing settings when it cannot vend
    credentials (R2 and SeaweedFS have no STS). Fibrik already holds S3
    credentials through the storage profile, so data files are read and
    written directly with PyArrow instead.
    """

    def __init__(self, name: str, own_io: dict[str, str], **properties: str):
        self._own_io = own_io
        super().__init__(name, **properties)

    def _load_file_io(self, properties=None, location: str | None = None) -> FileIO:
        props = own_io_properties(dict(properties or {}), self._own_io)
        props["py-io-impl"] = "pyiceberg.io.pyarrow.PyArrowFileIO"
        return super()._load_file_io(props, location)


def ensure_warehouse(s: Settings) -> None:
    """Create the Lakekeeper warehouse that points at the storage profile."""
    if s.catalog_type != "rest":
        return
    st = s.storage
    base = s.catalog_management_uri.rstrip("/")
    with httpx.Client(timeout=30) as http:
        http.post(f"{base}/v1/bootstrap", json={"accept-terms-of-use": True})
        existing = http.get(f"{base}/v1/warehouse").raise_for_status().json()
        names = {w.get("name") for w in existing.get("warehouses", [])}
        if s.warehouse in names:
            return
        profile = {
            "type": "s3",
            "bucket": st.bucket,
            "region": st.region,
            "key-prefix": "lake",
            "path-style-access": st.path_style,
            "sts-enabled": False,
            "flavor": "s3-compat" if st.endpoint else "aws",
        }
        if st.endpoint:
            profile["endpoint"] = st.endpoint
        body = {
            "warehouse-name": s.warehouse,
            "storage-profile": profile,
            "storage-credential": {
                "type": "s3",
                "credential-type": "access-key",
                "aws-access-key-id": st.access_key_id,
                "aws-secret-access-key": st.secret_access_key,
            },
        }
        r = http.post(f"{base}/v1/warehouse", json=body)
        if r.status_code >= 400:
            raise RuntimeError(f"creating warehouse failed: {r.status_code} {r.text}")
        log.info("created warehouse %s", s.warehouse)


def get_catalog(s: Settings, **extra: str) -> Catalog:
    if s.catalog_type == "sql":
        props = {"uri": s.catalog_uri, "warehouse": f"s3://{s.storage.bucket}/lake"}
        return load_catalog("fibrik", type="sql", **(props | _io_properties(s) | extra))
    return FibrikRestCatalog(
        "fibrik",
        own_io=_io_properties(s),
        uri=s.catalog_uri,
        warehouse=s.warehouse,
        **extra,
    )


def ensure_table(catalog: Catalog, s: Settings) -> Table:
    try:
        catalog.create_namespace(s.lake_namespace)
    except NamespaceAlreadyExistsError:
        pass
    return catalog.create_table_if_not_exists(
        (s.lake_namespace, RAW_LOGS), schema=ICEBERG_SCHEMA, partition_spec=PARTITION_SPEC
    )
