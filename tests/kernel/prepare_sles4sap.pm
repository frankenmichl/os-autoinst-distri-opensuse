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

    # check we are really using btrfs
    assert_script_run('mount | grep "on / type btrfs"');

    # add second disk to /
    assert_script_run("btrfs device add -f /dev/sdb /");

}

1;
