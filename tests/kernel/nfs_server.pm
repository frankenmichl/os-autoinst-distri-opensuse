# SUSE's openQA tests
#
# Copyright 2023-2026 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: NFS server
#    This module provisions the NFS server and then runs some basic sanity tests
#    NFS server - provisioned on SUSE/openSUSE - provides specific exports:
#      - NFS v3 with sync and async flags
#      - NFS v4 with sync and async flags
#    NFS client (tests/kernel/nfs_client.pm) creates a file using dd and then copies
#    that file to all exports mounted on the client side.
#    Data integrity of the file is checked with the md5 checksum.
#
#    An extension to the NFS tests uses dd for copying the created file using various flags:
#      - direct
#      - dsync
#      - sync
#    The earlier created file is copied with each flag to each mounted export and the md5 checksum
#    is used again to check data integrity for each file copied with dd using every flag.

# Maintainer: Kernel QE <kernel-qa@suse.de>

use Mojo::Base 'opensusebasetest';
use testapi;
use serial_terminal "select_serial_terminal";
use lockapi;
use utils;
use Utils::Logging "export_logs_basic";
use Kernel::nfs;
use package_utils "install_package";

sub run {
    my ($self) = @_;
    my $client = get_var('CLIENT_NODE', 'client-node00');

    select_serial_terminal();
    record_info('hostname', script_output('hostname'));

    my $nfs_permissions = get_var('NFS_PERMISSIONS', 'rw,sync,no_root_squash');
    my $nfs_permissions_async = get_var('NFS_PERMISSIONS_ASYNC', 'rw,async,no_root_squash');

    install_package('nfs-kernel-server', trup_continue => 1);

    my @versions_to_check = qw(V3 V4);
    my @active_shares;

    foreach my $ver (@versions_to_check) {
        next unless verify_nfs_support(version => $ver, is_server => 1);

        record_info('INFO', "Kernel and config support $ver server");

        my $path_sync = get_var("NFS_SHARE_${ver}", "/nfs/shared_${ver}");
        my $path_async = $path_sync . '_async';

        create_mount_and_export($path_sync, $client, $nfs_permissions);
        create_mount_and_export($path_async, $client, $nfs_permissions_async);

        push @active_shares, ($path_sync, $path_async);
    }

    record_info('EXPORTS', script_output('cat /etc/exports'));

    systemctl('enable rpcbind --now');
    systemctl('is-active rpcbind');
    systemctl('enable nfs-server --now');
    systemctl('restart nfs-server');
    systemctl('is-active nfs-server');

    record_info('RPC', script_output('rpcinfo'));
    record_info('NFS config', script_output('cat /etc/sysconfig/nfs'));
    record_info('NFS stat for server', script_output('nfsstat -s'));

    barrier_wait('NFS_SERVER_ENABLED');
    barrier_wait('NFS_SERVER_CHECK');

    foreach my $share (@active_shares) {
        nfs_verify_checksums($share);
    }

    record_info('NFS stat for server', script_output('nfsstat -s'));
}

sub test_flags {
    return {fatal => 1, milestone => 1};
}

sub post_fail_hook {
    my ($self) = @_;
    $self->destroy_test_barriers();
    select_serial_terminal;
    export_logs_basic;
}

1;
