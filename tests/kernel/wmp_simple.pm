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

sub run {
    my $self = shift;
    my @sap_processes = split(',', get_required_var('SAP_PROCESSES'));
    my $eat_amount = get_required_var('MEMEATER_AMOUNT');

    $self->select_serial_terminal;

    # we need a compiler
    zypper_call "ar -f https://download.opensuse.org/repositories/home:/MMoese/SLE_15/home:MMoese.repo";
    zypper_call "in memeater";

    # consume memory in the background
    assert_script_run "memeater -m $eat_amount -n";

    my @processes = script_output("ls /proc/*/status");

    foreach(@sap_processes) {
        my @pids = split(' ', script_output("pgrep $_"));

        foreach (@pids) {
            assert_script_run("grep \"VmSwap:[[:blank:]]*0 kB\"  /proc/$_/status");
        }
    }
}

1;
