# SUSE's openQA tests
#
# Copyright 2023-2025 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: NFS server
#    This module provisions the NFS server and then runs some basic sanity tests
#    NFS server - provisioned on SUSE/openSUSE - provides specific exports:
#      - NFS v3 with sync and async flags
#      - NFS v4 with sync and async flags
#    NFS client (tests/kernel/nfs_client.pm) creates a file using dd tool and then copies
#    that file to all exports mounted on the client side.
#    Data integrity of the file is checked with the md5 checksum
#
#    Extension to the NFS tests uses dd tool for copying created file using various flags,
#    specifically:
#      - direct
#      - dsync
#      - sync
#    An earlier created file is copied with each flag to each mounted export and then md5 checksum is
#    used again to check data integridty for each file copied with dd tool with all each flag

# Maintainer: Kernel QE <kernel-qa@suse.de>

use Mojo::Base "opensusebasetest";
use testapi;
use serial_terminal "select_serial_terminal";
use lockapi;
use utils;
use Utils::Logging "export_logs_basic";
use Kernel::nfs;

# helper:; verify checksums of a list of files
sub nfs_verify_server_data {
    my ($mount_path) = @_;
    my @flags = qw(direct dsync sync);

    record_info("VERIFY", "Checking data integrity in $mount_path");
    assert_script_run("cd $mount_path && md5sum -c md5sum.txt");
    my $expected_md5 = script_output("cut -d ' ' -f1 $mount_path/md5sum.txt");
    foreach my $flag (@flags) {
        my $file = "testfile_oflag_$flag";
        assert_script_run("echo '$expected_md5  $file' | md5sum -c -",
            fail_message => "Checksum mismatch for $file in $mount_path");
    }
}


sub run {
    my $self = @_;
    my $client = get_var('CLIENT_NODE', 'client-node00');

    select_serial_terminal();
    record_info("hostname", script_output("hostname"));

    my $nfs_mount_nfs3 = get_var('NFS_MOUNT_NFS3', '/nfs/shared_nfs3');
    my $nfs_mount_nfs3_async = get_var('NFS_MOUNT_NFS3_ASYNC', '/nfs/shared_nfs3_async');
    my $nfs_mount_nfs4 = get_var('NFS_MOUNT_NFS4', '/nfs/shared_nfs4');
    my $nfs_mount_nfs4_async = get_var('NFS_MOUNT_NFS4_ASYNC', '/nfs/shared_nfs4_async');

    my $nfs_permissions = get_var('NFS_PERMISSIONS', 'rw,sync,no_root_squash');
    my $nfs_permissions_async = get_var('NFS_PERMISSIONS_ASYNC', 'rw,async,no_root_squash');

    # following files are copied on the client side using dd with specific flags: direct, dsync, sync
    my $file_flag_direct = 'testfile_oflag_direct';
    my $file_flag_dsync = 'testfile_oflag_dsync';
    my $file_flag_sync = 'testfile_oflag_sync';

    # provision NFS server(s) of various types
    zypper_call("in nfs-kernel-server");

    # configure our exports
    if (verify_nfs_support('V3', server => 1)) {
        record_info('INFO', 'Kernel has support for NFSv3');
        create_export($nfs_mount_nfs3, $client, $nfs_permissions);
        create_export($nfs_mount_nfs3_async, $client, $nfs_permissions_async);
    }
    if (verify_nfs_support('V4', server => 1)) {
        record_info('INFO', 'Kernel has support for NFSv4');
        create_export($nfs_mount_nfs4, $client, $nfs_permissions);
        create_export($nfs_mount_nfs4_async, $client, $nfs_permissions_async);
    }

    record_info("EXPORTS", script_output("cat /etc/exports"));

    systemctl("enable rpcbind --now");
    systemctl("is-active rpcbind");
    systemctl("enable nfs-server --now");
    systemctl("restart nfs-server");
    systemctl("is-active nfs-server");

    record_info("RPC", script_output("rpcinfo"));
    record_info("NFS config", script_output("cat /etc/sysconfig/nfs"));

    #my $nfsstat = script_output("nfsstat -s");
    record_info("NFS stat for server", script_output("nfsstat -s"));

    barrier_wait("NFS_SERVER_ENABLED");
    barrier_wait("NFS_SERVER_CHECK");

    if (verify_nfs_support('V3', server => 1) == 1) {
        #checking files in /nfs/shared_nfs3
        record_info("TESTS: NFS3");
        record_info("NFS3 list all files", script_output("ls $nfs_mount_nfs3"));

        assert_script_run("cd $nfs_mount_nfs3");

        assert_script_run("md5sum -c md5sum.txt");
        record_info("NFS3 checksum", script_output("md5sum -c md5sum.txt"));
        record_info("NFS3 checksum", script_output("cat md5sum.txt"));

        #check files copied with various flags: direct, dsync, sync
        compare_checksums($file_flag_direct);
        compare_checksums($file_flag_dsync);
        compare_checksums($file_flag_sync);

        #checking files in /nfs/shared_nfs3_async
        record_info("TESTS: NFS3 async");

        assert_script_run("cd $nfs_mount_nfs3_async");
        assert_script_run("md5sum -c md5sum.txt");
        record_info("NFS3 async checksum", script_output("md5sum -c md5sum.txt"));

        #check files copied with various flags: direct, dsync, sync
        compare_checksums($file_flag_direct);
        compare_checksums($file_flag_dsync);
        compare_checksums($file_flag_sync);
    }

    if (verify_nfs_support('V4', server => 1) == 1) {
        #checking files in /nfs/shared_nfs4
        record_info("TESTS: NFS4");

        assert_script_run("cd $nfs_mount_nfs4");
        assert_script_run("md5sum -c md5sum.txt");
        record_info("NFS4 checksum", script_output("md5sum -c md5sum.txt"));

        #check files copied with various flags: direct, dsync, sync
        compare_checksums($file_flag_direct);
        compare_checksums($file_flag_dsync);
        compare_checksums($file_flag_sync);

        #checking files in /nfs/shared_nfs4_async
        record_info("TESTS: NFS4 async");

        assert_script_run("cd $nfs_mount_nfs4_async");
        assert_script_run("md5sum -c md5sum.txt");
        record_info("NFS4 async checksum", script_output("md5sum -c md5sum.txt"));

        #check files copied with various flags: direct, dsync, sync
        compare_checksums($file_flag_direct);
        compare_checksums($file_flag_dsync);
        compare_checksums($file_flag_sync);
    }

    record_info("NFS stat for server", script_output("nfsstat -s"));
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
