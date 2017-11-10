# --------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See License.txt in the project root for license information.
# --------------------------------------------------------------------------------------------
 
from azure.cli.core.help_files import helps
from azure.cli.core.commands import (register_cli_argument,register_extra_cli_argument)

helps['aliyunmigration'] = """
    type: group
    short-summary: Migrate Aliyun resources
"""

helps['aliyunmigration storage migrate'] = """
    type: command
    short-summary: Migrate Aliyun Storage
"""

def load_params(_):
    register_cli_argument('aliyunmigration storage migrate', 'aliyun_access_id', help='aliyun access id')
    register_cli_argument('aliyunmigration storage migrate', 'aliyun_secret_key', help='aliyun secret key')
    register_cli_argument('aliyunmigration storage migrate', 'aliyun_region_endpoint', help='aliyun region endpoint')
    register_cli_argument('aliyunmigration storage migrate', 'aliyun_bucket_name', help='aliyun bucket name')
    register_cli_argument('aliyunmigration storage migrate', 'azure_storage_acount_name', help='azure storage acount name')
    register_cli_argument('aliyunmigration storage migrate', 'azure_storage_account_key', help='azure storage account key')
    register_cli_argument('aliyunmigration storage migrate', 'azure_storage_endpoint', help='azure storage endpoint')
    register_cli_argument('aliyunmigration storage migrate', 'azure_storage_container_name', help='azure storage container name')
    register_extra_cli_argument('aliyunmigration storage migrate', 'server_side_copy', action='store_true', help='perform server side copy')
    register_extra_cli_argument('aliyunmigration storage migrate', 'tempdir', help='directory to store temporary files')

def load_commands():
    from azure.cli.core.commands import cli_command
    cli_command(__name__, 'aliyunmigration storage migrate', 'azext_aliyunmigration.storage#migrate')
