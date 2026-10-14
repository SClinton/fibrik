"""Object storage access through the storage profile.

Only the S3 API is implemented for the MVP. S3 covers AWS, Cloudflare R2,
OCI Object Storage, Ceph RGW, SeaweedFS and MinIO; native GCS and Azure
types are post-MVP (initial-stack.md §1).
"""

from dataclasses import dataclass

import pyarrow.fs as pafs

from fibrik.settings import StorageSettings


@dataclass(frozen=True)
class ObjectInfo:
    key: str
    size: int


class ObjectStore:
    def __init__(self, cfg: StorageSettings):
        self.cfg = cfg
        endpoint = cfg.endpoint or None
        scheme = "https"
        if endpoint and "://" in endpoint:
            scheme, endpoint = endpoint.split("://", 1)
        self.fs = pafs.S3FileSystem(
            access_key=cfg.access_key_id or None,
            secret_key=cfg.secret_access_key or None,
            endpoint_override=endpoint,
            scheme=scheme,
            region=cfg.region,
            force_virtual_addressing=not cfg.path_style,
        )

    def _path(self, key: str) -> str:
        return f"{self.cfg.bucket}/{key}"

    def ensure_bucket(self) -> None:
        info = self.fs.get_file_info(self.cfg.bucket)
        if info.type == pafs.FileType.NotFound:
            self.fs.create_dir(self.cfg.bucket)

    def list(self, prefix: str) -> list[ObjectInfo]:
        selector = pafs.FileSelector(self._path(prefix), recursive=True, allow_not_found=True)
        out = []
        for info in self.fs.get_file_info(selector):
            if info.type == pafs.FileType.File:
                out.append(ObjectInfo(info.path.removeprefix(f"{self.cfg.bucket}/"), info.size))
        return sorted(out, key=lambda o: o.key)

    def read(self, key: str) -> bytes:
        with self.fs.open_input_file(self._path(key)) as f:
            return f.read()

    def move(self, key: str, new_key: str) -> None:
        self.fs.copy_file(self._path(key), self._path(new_key))
        self.fs.delete_file(self._path(key))

    def uri(self, key: str = "") -> str:
        return f"s3://{self.cfg.bucket}/{key}"
