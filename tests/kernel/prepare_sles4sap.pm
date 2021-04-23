# SUSE's openQA tests
#
# Copyright © 2021 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# do some additional preparations for sles4sap testing on our baremetal machines
#
# Maintainer: Michael Moese <mmoese@suse.de>

use base 'opensusebasetest';
use strict;
use warnings;
use testapi;
use utils;


sub run {
    my $self = shift;

    $self->select_serial_terminal;

    my $disk = script_output('TMP=$(pvdisplay -C -o pv_name,vg_name | grep system | cut -d \' \' -f 3); echo ${TMP::-1}');
    my $part = $disk . "3";
    my $is_hana = script_run("pvdisplay -C -o pv_name,vg_name | grep vg_hana");

    assert_script_run("echo ',,V' | sfdisk $disk --force --append");
    assert_script_run("partprobe");
    assert_script_run("pvcreate $part");
    assert_script_run("vgextend vg_hana $part");
    assert_script_run("lvextend -L +63G /dev/vg_hana/lv_hanashared");
    assert_script_run("xfs_growfs /hana/shared");
    assert_script_run("lvextend -L +63G /dev/vg_hana/lv_hanadata");
    assert_script_run("xfs_growfs /hana/data");

}

1;
