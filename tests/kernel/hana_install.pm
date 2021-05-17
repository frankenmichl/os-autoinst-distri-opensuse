# SUSE's SLES4SAP openQA tests
#
# Copyright © 2019-2021 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Package: lvm2 util-linux parted device-mapper
# Summary: Install HANA via command line. Verify installation with
# sles4sap/hana_test
# Maintainer: Alvaro Carvajal <acarvajal@suse.com>

use base 'sles4sap';
use strict;
use warnings;
use testapi;
use utils qw(file_content_replace zypper_call);
use Utils::Systemd 'systemctl';
use version_utils 'is_sle';
use POSIX 'ceil';

sub run {
    my ($self) = @_;
    my ($proto, $path) = $self->fix_path(get_required_var('HANA'));
    my $sid          = get_required_var('INSTANCE_SID');
    my $instid       = get_required_var('INSTANCE_ID');
    my $reclaim_root = get_var('RECLAIM_ROOT', 0);

    $self->select_serial_terminal;
    my $RAM = $self->get_total_mem();
    die "RAM=$RAM. The SUT needs at least 24G of RAM" if $RAM < 24000;

    zypper_call('in SAPHanaSR SAPHanaSR-doc ClusterTools2') if get_var('HA_CLUSTER');

    # Add host's IP to /etc/hosts
    $self->add_hostname_to_hosts;

    # Install libopenssl1_0_0 for older (<SPS03) HANA versions on SLE15+
    $self->install_libopenssl_legacy($path);

    # This installs HANA. Start by configuring the appropiate SAP profile
    $self->prepare_profile('HANA');

    # Copy media
    my $tout = get_var('HANA_INSTALLATION_TIMEOUT', 2700);    # Timeout for HANA installation commands. Defaults to NW's timeout times 2
    $self->copy_media($proto, $path, $tout, '/sapinst');

    # Mount points information: use the same paths and minimum sizes as the wizard (based on RAM size)
    my $full_size = ceil($RAM / 1024);                        # Use the ceil value of RAM in GB
    my $half_size = ceil($full_size / 2);
    my $volgroup  = 'vg_hana';
    my %mountpts  = (
        hanadata   => {mountpt => '/hana/data',         size => "${full_size}g"},
        hanalog    => {mountpt => '/hana/log',          size => "${half_size}g"},
        hanashared => {mountpt => '/hana/shared',       size => "${full_size}g"},
        usr_sap    => {mountpt => "/usr/sap/$sid/home", size => '50g'}
    );

    # hdblcm is used for installation, verify if it exists
    my $hdblcm = '/sapinst/' . get_var('HANA_HDBLCM', "DATA_UNITS/HDB_SERVER_LINUX_" . uc(get_required_var('ARCH')) . "/hdblcm");
    die "hdblcm is not in [$hdblcm]. Set HANA_HDBLCM to the appropiate relative path. Example: DATA_UNITS/HDB_SERVER_LINUX_X86_64/hdblcm"
      if (script_run "ls $hdblcm");

    # Install hana
    my @hdblcm_args = qw(--autostart=n --shell=/bin/sh --workergroup=default --system_usage=custom --batch
      --hostname=$(hostname) --db_mode=multiple_containers --db_isolation=low --restrict_max_mem=n
      --userid=1001 --groupid=79 --use_master_password=n --skip_hostagent_calls=n --system_usage=production);
    push @hdblcm_args,
      "--sid=$sid",
      "--number=$instid",
      "--home=$mountpts{usr_sap}->{mountpt}",
      "--password=$sles4sap::instance_password",
      "--system_user_password=$sles4sap::instance_password",
      "--sapadm_password=$sles4sap::instance_password",
      "--datapath=$mountpts{hanadata}->{mountpt}/$sid",
      "--logpath=$mountpts{hanalog}->{mountpt}/$sid",
      "--sapmnt=$mountpts{hanashared}->{mountpt}";
    my $cmd = join(' ', $hdblcm, @hdblcm_args);
    record_info 'hdblcm command', $cmd;
    assert_script_run $cmd, $tout;

    # Upload installations logs
    $self->upload_hana_install_log;

    # Quick check of block/filesystem devices after installation
    assert_script_run 'mount';
    assert_script_run 'lvs -ao +devices';
}

sub test_flags {
    return {fatal => 1};
}

1;
