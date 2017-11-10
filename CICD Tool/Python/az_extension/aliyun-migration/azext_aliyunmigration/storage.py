""" oss to azure """
import tempfile
import sys
import os
import json
import uuid
import shutil
import urllib3
import oss2
import azure.storage.blob
import azure.common

TELEMETRY_SERVICE = "http://azuremigtooltelemetryservice.trafficmanager.cn//api/telemetry/"
HTTP = urllib3.PoolManager()

def _telemetry(data):
    url = TELEMETRY_SERVICE + data["TelemetryType"]
    HTTP.request(
        'POST', url,
        headers={'Content-Type': 'application/json'},
        body=json.dumps(data))


def _get_percentage_function(file_name):
    def _percentage(consumed_bytes, total_bytes):
        if total_bytes:
            rate = int(100 * (float(consumed_bytes) / float(total_bytes)))
            sys.stdout.write('\r%s: %d%% ' % (file_name, rate))
            sys.stdout.flush()
    return _percentage


def transfer_to_azure_server_side(session, aliyun_client, azure_client, container_name):
    """
    Copy file from Aliyun OSS to Azure Storage directly
    """
    sys.stdout.write('Begin copying files to Azure storage...\n')
    sys.stdout.flush()

    blob_count = 0
    bytes_copied = 0

    for obj in oss2.ObjectIterator(aliyun_client):
        if obj.key[-1] != '/':
            url = aliyun_client.sign_url('GET', obj.key, 60)
            try:
                copy = azure_client.get_blob_properties(container_name, obj.key).properties.copy
                if copy.status == 'pending':
                    azure_client.abort_copy_blob(container_name, obj.key, copy.id)
            except azure.common.AzureMissingResourceHttpError:
                # Destination blob doesn't exist
                pass
            _telemetry({
                "SessionID": session,
                "TelemetryType": "ServerSideBlobCopyingBegin"
            })
            azure_client.copy_blob(container_name, obj.key, url)
            sys.stdout.write("%s\n" % obj.key)
            sys.stdout.flush()

            blob_count += 1
            # BUG: How to get blob size w/o downloading? Following line seems to always return 0.
            byc = azure_client.get_blob_properties(container_name, obj.key).properties.content_length
            _telemetry({
                "SessionID": session,
                "TelemetryType": "ServerSideBlobCopyEnd",
                "BytesCopied": byc,
                "IsSuccessful": True
            })
            bytes_copied += byc

    return (blob_count, bytes_copied)


def transfer_to_azure(session, aliyun_client, azure_client, container_name, directory=None):
    """
    Download file from Aliyun OSS to local then upload to Azure Storage
    """
    sys.stdout.write('Begin copying files to azure storage...\n')
    sys.stdout.flush()

    blob_count = 0
    bytes_copied = 0

    try:
        for obj in oss2.ObjectIterator(aliyun_client):
            temp_dir = tempfile.mkdtemp(dir=directory)
            if obj.key[-1] != '/':
                try:
                    with tempfile.NamedTemporaryFile(dir=temp_dir, delete=False) as tmpfile:
                        temp_name = tmpfile.name
                        tmpfile.close()
                    sys.stdout.write("\nDownloading file '%s':\n" % obj.key)
                    sys.stdout.flush()
                    _telemetry({
                        "SessionID": session,
                        "TelemetryType": "BlobDownloadingBegin"
                    })
                    aliyun_client.get_object_to_file(
                        obj.key,
                        temp_name,
                        progress_callback=_get_percentage_function(obj.key))
                    _telemetry({
                        "SessionID": session,
                        "TelemetryType": "BlobDownloadingEnd"
                    })
                    sys.stdout.write("\nUploading file '%s':\n" % obj.key)
                    sys.stdout.flush()
                    _telemetry({
                        "SessionID": session,
                        "TelemetryType": "BlobUploadingBegin"
                    })
                    azure_client.create_blob_from_path(
                        container_name,
                        obj.key,
                        temp_name,
                        progress_callback=_get_percentage_function(obj.key))
                    sys.stdout.write("\n")
                    sys.stdout.flush()
                    blob_count += 1
                    byc = azure_client.get_blob_properties(container_name, obj.key).properties.content_length
                    _telemetry({
                        "SessionID": session,
                        "TelemetryType": "BlobUploadingEnd",
                        "BytesCopied": byc,
                        "IsSuccessful": True
                    })
                    bytes_copied += byc
                finally:
                    os.remove(temp_name)
    finally:
        shutil.rmtree(temp_dir)

    return (blob_count, bytes_copied)

def migrate(aliyun_access_id,
            aliyun_secret_key,
            aliyun_region_endpoint,
            aliyun_bucket_name,
            azure_storage_acount_name,
            azure_storage_account_key,
            azure_storage_endpoint,
            azure_storage_container_name,
            server_side_copy=True,
            tempdir=None):
    """
    Copy file from Aliyun OSS to Azure Storage
    """
    session = str(uuid.uuid4())
    successful = False
    message = ""
    blob_count = 0
    bytes_copied = 0
    try:
        _telemetry({
            "SessionID": session,
            "TelemetryType":"SessionBegin",
            "ServerSideCopy": server_side_copy
        })
        if tempdir == "":
            tempdir = None
        aliyun_auth = oss2.Auth(aliyun_access_id, aliyun_secret_key)
        aliyun_client = oss2.Bucket(aliyun_auth, aliyun_region_endpoint, aliyun_bucket_name)
        azure_client = azure.storage.blob.BlockBlobService(
            account_name=azure_storage_acount_name,
            account_key=azure_storage_account_key,
            endpoint_suffix=azure_storage_endpoint)

        if server_side_copy:
            (blc, byc) = transfer_to_azure_server_side(
                session,
                aliyun_client,
                azure_client,
                azure_storage_container_name)
        else:
            (blc, byc) = transfer_to_azure(
                session,
                aliyun_client,
                azure_client,
                azure_storage_container_name,
                directory=tempdir)
        blob_count += blc
        bytes_copied += byc
        successful = True
    except oss2.exceptions.OssError as err:
        message = err.message
        sys.stderr.write(err.message)
        sys.stderr.flush()
    except azure.common.AzureException as err:
        message = str(err)
        sys.stderr.write("Error: %s\n" % message, file=sys.stderr)
        sys.stderr.flush()
    finally:
        _telemetry(
            {
                "SessionID": session,
                "TelemetryType":"SessionEnd",
                "Message": message,
                "ServerSideCopy": server_side_copy,
                "IsSuccessful": successful,
                "BlobCount": blob_count,
                "BytesCopied": bytes_copied
            }
        )
