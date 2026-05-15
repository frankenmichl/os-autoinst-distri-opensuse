# Copyright 2026 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Kernel::nfs;

use base Exporter;
use Exporter;

use strict;
use warnings;
use testapi;

our @EXPORT = qw(
  verify_nfs_support
  mount_share
  create_mount_and_export
  nfs_verify_checksums
);

=head1 SYNOPSIS

Utilities for NFS tests.

=cut

=head2 verify_nfs_support

  verify_nfs_support([version => 'V3'], [is_server => 0]);

Verifies that the kernel has the expected NFS/NFSD config option for the
requested test variant.

This helper is intentionally strict:
- If the corresponding C<NFS..._ENABLED> variable disables the version,
  the check is skipped and the function returns C<0>.
- If the version is enabled but the required kernel config option is missing,
  the function dies.
- Otherwise the function returns C<1>.

This is used not only to decide whether a test variant can run, but also to
catch distribution kernel configuration regressions early.

Parameters:
- C<version>: NFS version to validate (e.g. C<V3>, C<V4>, C<V4.1>, C<V4.2>).
  Default: C<V3>.
- C<is_server>: If true, validate server-side NFSD support. Otherwise validate
  client-side NFS support. Default: C<0>.

Notes:
- Client-side checks are version-specific and validate the corresponding
  C<CONFIG_NFS_*> option.
- Server-side checks validate generic NFSD support. For Linux kernels, all
  C<V4*> variants map to C<CONFIG_NFSD_V4>.

=cut
sub verify_nfs_support {
    my %args = @_;
    my $ver = uc($args{version} // 'V3');
    my $is_server = $args{is_server} // 0;

    my $clean_ver = $ver =~ s/[^A-Z0-9]//gr;
    my $var_name = "NFS${clean_ver}_ENABLED";

    if (get_var($var_name, '1') eq '0') {
        record_info('INFO', "$ver is disabled via $var_name. Skipping.");
        return 0;
    }

    die 'FATAL: /proc/config.gz missing! Cannot verify NFS kernel config.'
      if script_run('test -f /proc/config.gz') != 0;

    my $config_key;
    if ($is_server) {
        $config_key = ($ver =~ /^V4/) ? 'CONFIG_NFSD_V4' : 'CONFIG_NFSD';
    } else {
        (my $suffix = $ver) =~ s/\./_/g;
        $config_key = "CONFIG_NFS_$suffix";
    }

    if (script_run("zgrep -q '$config_key=[my]' /proc/config.gz") != 0) {
        die "FATAL: Expected kernel option $config_key for $ver is missing while $var_name is enabled.";
    }

    record_info('INFO', "Verified kernel support for $ver via $config_key");
    return 1;
}

=head2 mount_share

  mount_share($server, $share, $local, $opts);

Creates a local directory and mounts an NFS share with the given options.

Parameters:
- C<server>: Hostname or IP of the NFS server.
- C<share>: Remote path exported by the server.
- C<local>: Local mount point (will be created with C<mkdir -p>).
- C<opts>: Mount options string (e.g. C<nfsvers=4.2,nosuid>).

=cut
sub mount_share {
    my ($server, $share, $local, $opts) = @_;
    assert_script_run("mkdir -p $local");
    assert_script_run("mount -t nfs -o $opts $server:$share $local");
}

=head2 create_mount_and_export

  create_mount_and_export($mountpoint, $client, $permissions);

Creates a local directory with open permissions and appends a corresponding
entry to F</etc/exports>.

Parameters:
- C<mountpoint>: Local path to be created and exported.
- C<client>: Client specification (e.g. C<*> or a specific network/IP).
- C<permissions>: Export options (e.g. C<rw,sync,no_root_squash>).

=cut
sub create_mount_and_export {
    my ($mountpoint, $client, $permissions) = @_;

    assert_script_run("mkdir -p $mountpoint");
    assert_script_run("chmod 777 $mountpoint");
    assert_script_run("echo $mountpoint $client\\($permissions\\) >> /etc/exports");
}

=head2 nfs_verify_checksums

  nfs_verify_checksums($path);

Verifies NFS file integrity for sync, dsync, and direct I/O flags at the given
path. Logs the directory content and validates checksums against the local
C<md5sum.txt>.

Parameters:
- C<path>: The mount point or subdirectory to verify.

=cut
sub nfs_verify_checksums {
    my ($path) = @_;
    my @flags = qw(direct dsync sync);

    my $ls_output = script_output("ls -la $path");
    record_info('Verify: ' . (split('/', $path))[-1], "Path: $path\n\n$ls_output");

    assert_script_run("test -f $path/md5sum.txt");
    assert_script_run("cd $path && md5sum -c md5sum.txt");

    foreach my $flag (@flags) {
        my $file = "testfile_oflag_$flag";
        my $expected = script_output("grep -w '$file' $path/md5sum.txt | cut -d ' ' -f1");
        my $actual = script_output("md5sum $path/$file | cut -d ' ' -f1");

        die "Checksum mismatch in $path for $file!\nExpected: $expected\nActual:   $actual"
          if $expected ne $actual;
    }
}

1;
