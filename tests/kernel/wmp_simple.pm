# SUSE's openQA tests
#
# Copyright © 2021 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# 
# Summary: consume memory and make sure selected process don't get swapped
#          
# Maintainer: Michael Moese <mmoese@suse.de>
# Tags: https://progress.opensuse.org/issues/49031

use base 'opensusebasetest';
use strict;
use warnings;
use testapi;
use utils;
use Mojo::Util 'trim';

sub run {
    my $self = shift;
    my $meminfo;
    my $failed;
    $self->select_serial_terminal;

    zypper_ar("https://download.opensuse.org/repositories/benchmark/SLE_15_SP3/benchmark.repo", no_gpg_check => 1); 
    zypper_call("in stress-ng");

    #assert_script_run('sysctl vm.swappiness=100');

    # configure memory.low
    assert_script_run("systemctl set-property SAP.slice MemoryLow=32G");

    # start hana again and wait for the memory consumption to settle
    assert_script_run('sudo -u ndbadm bash -c "/usr/sap/NDB/HDB00/exe/sapcontrol -nr 00 -function StartSystem ALL"');


    # wait until memory usage of HANA settled, this takes > 5 minutes, so give it 15 minutes
    sleep 300;

    # consume memory in the background
    #background_script_run('stress-ng --vm-bytes 41G --vm-keep -m 1');
    background_script_run('stress-ng --vm-bytes $(awk \'/MemAvailable/{printf "%d\n", $2 * 1.05;}\' < /proc/meminfo)k --vm-keep -m 1');

    sleep 300;

    $meminfo = script_output("cat /proc/meminfo");
    record_info("meminfo", "$meminfo");

    my $scope = trim(script_output('systemd-cgls -u SAP.slice | grep \'wmp-.*.scope\' | cut -c 3-'));

    my @pids = split(' ', script_output("cat /sys/fs/cgroup/SAP.slice/$scope/cgroup.procs"));

    foreach (@pids) {
            my $vmswap = trim(script_output("grep \"VmSwap:\"  /proc/$_/status | cut -d ':' -f 2"));
	    my $cmdline = trim(script_output("cat /proc/$_/cmdline"));

	    if ($vmswap eq "0 kB") {
		    record_info("not swapped", "Process $cmdline (Pid $_) is not using swap", result => 'ok');
	    } else {
		    record_info("swapped","Process $cmdline (Pid $_) is using $vmswap of swap", result => 'fail');
		    $failed = 1;
	    }
    }
    die "at least one process is using swap memory" if $failed;
    $meminfo = script_output("cat /proc/meminfo");
    record_info("meminfo", "$meminfo");
}

1;
