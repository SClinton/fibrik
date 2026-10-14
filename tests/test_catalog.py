from fibrik.lake.catalog import own_io_properties


def test_server_storage_hints_are_replaced_by_the_storage_profile():
    server = {
        "py-io-impl": "pyiceberg.io.fsspec.FsspecFileIO",
        "s3.remote-signing-enabled": "true",
        "s3.signer.uri": "http://lakekeeper:8181/catalog",
        "s3.endpoint": "http://other:9000",
        "write.parquet.compression-codec": "zstd",
    }
    own = {"s3.endpoint": "http://seaweedfs:8333", "s3.access-key-id": "k"}
    merged = own_io_properties(server, own)
    assert merged == {
        "write.parquet.compression-codec": "zstd",
        "s3.endpoint": "http://seaweedfs:8333",
        "s3.access-key-id": "k",
    }
