# Copyright 2025 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package Kernel::nfs;

use base Exporter;
use Exporter;

use strict;
use warnings;
use testapi;

our @EXPORT = qw(
  create_export
  verify_nfs_support
  mount_share
);

=head1 SYNOPSIS

Utils for NFS testing

=cut

=head2 create_export

 create_export($path, $client, $export_opts)

Create directory C<$path> and export it via NFS to C<$client>. C<$export_opts>
is written as the option list in F</etc/exports> (e.g. C<rw,sync,no_root_squash>).

=cut

sub create_export {
    my ($path, $client, $export_opts) = @_;

    assert_script_run "mkdir -p $path";
    assert_script_run "chmod 777 $path";
    assert_script_run "echo $path $client\\($export_opts\\) >> /etc/exports";
}


=head2 verify_nfs_support

  verify_nfs_support($version, [$is_server, $optional])

Checks if the kernel supports a specific NFS version.
Accepts: version => 'V3'|'V4'|'V4_1'|'V4_2', is_server => 0|1, defaults 0. Set 
$optional to 1 in order to softfail instead of failing if support is missing.

=cut

sub verify_nfs_support {
    my %args = @_;
    my $ver = $args{version} // 'V3';
    my $is_server = $args{is_server} // 0;
    my $optional = $args{optional} // 0;

    if (script_run('test -f /proc/config.gz') != 0) {
        my $msg = "/proc/config.gz missing! Kernel config not exported.";
        if ($optional) {
            record_soft_failure("CONFIG_MISSING: $msg");
            return 0;
        }
        record_info("config.gz not found", $msg, result => 'fail');
        die $msg;
    }

    my $config_key = $is_server
      ? (($ver =~ /V4/) ? "CONFIG_NFSD_V4" : "CONFIG_NFSD")
      : "CONFIG_NFS_$ver";

    if (script_run("zgrep '$config_key=[my]' /proc/config.gz") != 0) {
        my $info = "Flag: $config_key\nVersion: $ver\nRole: " . ($is_server ? "Server" : "Client");

        if ($optional) {
            record_soft_failure("NFS support misssing: $config_key missing");
            return 0;
        }

        record_info("NFS Supoport missing", $info, result => 'fail');
        die "FATAL: NFS support check failed for $config_key";
    }

    return 1;
}


=head2 mount_share 

  mount_share(($server, $share, $local, $opts)

Mount the directoy C<$share> exported by C<$server> to the path specified in C<$local>
using the moutn option C<$opts>.

=cut

sub mount_share {
    my ($server, $share, $local, $opts) = @_;
    return assert_script_run("mount -t nfs -o $opts $server:$share $local");
}

1;
