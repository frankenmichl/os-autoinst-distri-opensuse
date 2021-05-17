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

sub get_hana_device_from_system {
    my ($self, $disk_requirement) = @_;

    # Create a list of devices already configured as PVs to exclude them from the search
    my $out = script_output q@echo PV=$(pvscan -s 2>/dev/null | awk '/dev/ {print $1}' | tr '\n' ',')@;
    $out =~ /PV=(.+),$/;
    $out = $1;
    my @pvdevs = map { if ($_ =~ s@mapper/@@) { $_ =~ s/\-part\d+$// } else { $_ =~ s/\d+$// } $_ =~ s@^/dev/@@; $_; } split(/,/, $out);

    my $lsblk = q@lsblk -n -l -o NAME -d -e 7,11 | egrep -vw '@ . join('|', @pvdevs) . "'";
    # lsblk command to probe for devices is different when in multipath scenario
    $lsblk = q@lsblk -l -o NAME,TYPE -e 7,11 | awk '($2 == "mpath") {print $1}' | sort -u | egrep -vw '@ . join('|', @pvdevs) . "'" if is_multipath();

    # Probe devices, check its size and filter out the ones that do not meet the disk requirements
    my $devsize = 0;
    my $devpath = is_multipath() ? '/dev/mapper/' : '/dev/';
    my $device;
    my $filter_devices;
    while ($devsize < $disk_requirement) {
        $out = script_output "echo DEV=\$($lsblk | egrep -vw '$filter_devices' | head -1)";
        die "Could not find a suitable device for HANA installation." unless ($out =~ /DEV=([\w\.]+)$/);
        $device = $1;
        $filter_devices .= "|$device";
        $filter_devices =~ s/^\|//;
        $device = $devpath . $device;

        # Need to verify there is enough space in the device for HANA
        $out = script_output "echo SIZE=\$(lsblk -o SIZE --nodeps --noheadings --bytes $device)";
        die "Could not get size for [$device] block device." unless ($out =~ /SIZE=(\d+)$/);
        $devsize = $1;
        $devsize /= (1024 * 1024);    # Work in Mbytes since $RAM = $self->get_total_mem() is in Mbytes
    }

    return $device;
}

sub run {
    my ($self) = @_;
    my ($proto, $path) = $self->fix_path(get_required_var('HANA'));
    my $sid          = get_required_var('INSTANCE_SID');
    my $sid2         = get_var('INSTANCE_SID_2');
    my $reclaim_root = get_var('RECLAIM_ROOT', 0);

    $self->select_serial_terminal;

    # Mount points information: use the same paths and minimum sizes as the wizard (based on RAM size)
    my $full_size = ceil($RAM / 1024);      # Use the ceil value of RAM in GB
    my $half_size = ceil($full_size / 2);
    my $volgroup  = 'vg_hana';
    my %mountpts  = (
        hanadata   => {mountpt => '/hana/data',         size => "${full_size}g"},
        hanalog    => {mountpt => '/hana/log',          size => "${half_size}g"},
        hanashared => {mountpt => '/hana/shared',       size => "${full_size}g"},
        usr_sap    => {mountpt => "/usr/sap/$sid/home", size => '50g'}
    );

    $mountpoints{usr_sap_2} = {mountpt => "/usr/sap/$sid2/home", size => '50g'} if $sid2;

    # create mountpoints
    foreach (keys %mountpts) { assert_script_run "mkdir -p $mountpts{$_}->{mountpt}"; }

    # Partition disks for Hana

    # We need 2.5 times $RAM + 50G for HANA installation.
    $device = $self->get_hana_device_from_system(($RAM * 2.5) + 50000);
    record_info "Device: $device", "Will use device [$device] for HANA installation";
    script_run "wipefs -f $device; [[ -b ${device}1 ]] && wipefs -f ${device}1; [[ -b ${device}-part1 ]] && wipefs -f ${device}-part1";
    assert_script_run "parted --script $device --wipesignatures -- mklabel gpt mkpart primary 1 -1";

    # Remove traces of LVM structures from previous tests before configuring
    foreach my $lv_cmd ('lv', 'vg', 'pv') {
        my $looptime  = 20;
        my $lv_device = ($lv_cmd eq 'pv') ? $device : $volgroup;
        until (script_run "${lv_cmd}remove -f $lv_device 2>&1 | grep -q \"Can't open .* exclusively\.\"") {
            sleep bmwqemu::scale_timeout(2);
            last if (--$looptime <= 0);
        }
        if ($looptime <= 0) {
            record_info('ERROR', "Device $lv_device seems to be locked!", result => 'fail');
            # Just retry the $lv_cmd to have a "proper" error message
            script_run "${lv_cmd}remove -f $lv_device";
            die 'locked block device';    # We have to force the die, record_info don't do it
        }
    }
    foreach (keys %mountpts) { script_run "dmsetup remove $volgroup-lv_$_"; }

    # Now configure LVs and file systems for HANA
    assert_script_run "pvcreate -y $device";
    if ($reclaim_root) {
        # reuse unused space on / and add a physical volume to the volume groupt
        my $disk = script_output('for i in /dev/sd? ; do lsblk $i | grep system-root>/dev/null && echo $i; done');
        my $part = $disk . "3";
        assert_script_run("echo ',,V' | sfdisk $disk --force --append");
        assert_script_run("partprobe");
        assert_script_run("pvcreate $part");
        assert_script_run("vgextend vg_hana $part");
        assert_script_run "vgcreate -f $volgroup $device $part";
    } else {
        assert_script_run "vgcreate -f $volgroup $device";
    }
    foreach my $mounts (keys %mountpts) {
        assert_script_run "lvcreate -y -W y -n lv_$mounts --size $mountpts{$mounts}->{size} $volgroup";
        assert_script_run "mkfs.xfs -f /dev/$volgroup/lv_$mounts";
        assert_script_run "mount /dev/$volgroup/lv_$mounts $mountpts{$mounts}->{mountpt}";
        assert_script_run "echo /dev/$volgroup/lv_$mounts $mountpts{$mounts}->{mountpt} xfs defaults 0 0 >> /etc/fstab";
    }

    assert_script_run "df -h";
}

1;
