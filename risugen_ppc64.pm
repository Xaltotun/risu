#!/usr/bin/perl -w
###############################################################################
# Copyright (c) IBM Corp, 2016
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
#
# Contributors:
#     Jose Ricardo Ziviani (IBM) - ppc64 implementation
#     based on Peter Maydell (Linaro) - initial implementation
###############################################################################

# risugen -- generate a test binary file for use with risu
# See 'risugen --help' for usage information.
package risugen_ppc64;

use strict;
use warnings;

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(write_test_code);

my $periodic_reg_random = 1;

my $bytecount;
#
# Maximum alignment restriction permitted for a memory op.
my $MAXALIGN = 64;

sub open_bin
{
    my ($fname) = @_;
    open(BIN, ">", $fname) or die "can't open %fname: $!";
    $bytecount = 0;
}

sub insn32($)
{
    my ($insn) = @_;
    print BIN pack("V", $insn);
    $bytecount += 4;
}

sub close_bin
{
    close(BIN) or die "can't close output file: $!";
}

sub write_mov_ri16($$)
{
    my ($rd, $imm) = @_;

    # li rd,immediate
    insn32(0xe << 26 | $rd << 21 | $imm);
}

sub write_mov_ri32($$)
{
    my ($rd, $imm) = @_;

    # li rd,immediate@h
    write_mov_ri16($rd, ($imm >> 16) & 0xffff);
    # ori rd,rd,immediate@l
    insn32((0x18 << 26) | ($rd << 21) | ($rd << 16) | ($imm & 0xffff));
}

sub write_add_ri($$$)
{
    my ($rt, $ra, $imm) = @_;

    # addi rt, ra, immd
    insn32((0xe << 26) | ($rt << 21) | ($ra << 16) | ($imm & 0xffff));
}

sub write_mov_ri($$)
{
    # We always use a MOVW/MOVT pair, for simplicity.
    # on aarch64, we use a MOVZ/MOVK pair.
    my ($rd, $imm) = @_;

    if (($imm >> 16) & 0xffff) {
        write_mov_ri32($rd, $imm);
    } else {
        write_mov_ri16($rd, $imm);
    }

    #if ($is_aarch64 && $imm < 0) {
        # sign extend to allow small negative imm constants
    #    write_sxt32($rd, $rd);
    #}
}

sub write_random_ppc64_fpdata()
{
    # get an space from the stack
    insn32(0x3ac10020); # addi r22, r1, 32
    insn32(0x3ee03ff0); # lis r23, 0x3ff0
    insn32(0x3af70000); # addi r23, r23, 0
    insn32(0xfaf60000); # std r23, 0(r22)

    for (my $i = 0; $i < 32; $i++) {
        # lfd f$i, 0(r22)
        insn32((0x32 << 26 | $i << 21 | 0x16 << 16));
    }
}

sub write_random_regdata()
{
    # clear condition register
    for (my $i = 0; $i < 32; $i++) {
        # crxor i, i, i
        insn32((0x13 << 26) | ($i << 21) | ($i << 16) | ($i << 11) | (0xc1 << 1) | 0);
    }

    # general purpose registers
    for (my $i = 0; $i < 32; $i++) {
        if ($i == 1 || $i == 13) {
            next;
        }
        write_mov_ri($i, rand(0xffffffff));
    }
}

sub clear_vr_registers()
{
    # addi r22, r1, 32
    insn32(0x3ac10020);
    # li r23, 0
    write_mov_ri(23, 1);
    # std r23, 0(r22)
    insn32(0xfaf60000); 

    for (my $i = 0; $i < 32; $i++) {
        # vxor i, i, i
        insn32((0x4 << 26) | ($i << 21) | ($i << 16) | ($i << 11) | 0x4c4);
    }
}

my $OP_COMPARE = 0;        # compare registers
my $OP_TESTEND = 1;        # end of test, stop
my $OP_SETMEMBLOCK = 2;    # r0 is address of memory block (8192 bytes)
my $OP_GETMEMBLOCK = 3;    # add the address of memory block to r0
my $OP_COMPAREMEM = 4;     # compare memory block

sub write_random_register_data($)
{
    my ($fp_enabled) = @_;

    clear_vr_registers();

    if ($fp_enabled) {
        # load floating point / SIMD registers
        write_random_ppc64_fpdata();
    }

    write_random_regdata();
    write_risuop($OP_COMPARE);
}

sub write_memblock_setup()
{
    # li r2, 0
    write_mov_ri(2, 0);
    for (my $i = 0; $i < 10000; $i = $i + 8) {
        # std r2, 0(r1)
        my $imm = -$i;
        insn32((0x3e << 26) | (2 << 21) | (1 << 16) | ($imm & 0xffff));
    }
}

# Functions used in memory blocks to handle addressing modes.
# These all have the same basic API: they get called with parameters
# corresponding to the interesting fields of the instruction,
# and should generate code to set up the base register to be
# valid. They must return the register number of the base register.
# The last (array) parameter lists the registers which are trashed
# by the instruction (ie which are the targets of the load).
# This is used to avoid problems when the base reg is a load target.

# Global used to communicate between align(x) and reg() etc.
my $alignment_restriction;

sub is_pow_of_2($)
{
    my ($x) = @_;
    return ($x > 0) && (($x & ($x - 1)) == 0);
}

# sign-extract from a nbit optionally signed bitfield
sub sextract($$)
{
    my ($field, $nbits) = @_;

    my $sign = $field & (1 << ($nbits - 1));
    return -$sign + ($field ^ $sign);
}

sub align($)
{
    my ($a) = @_;
    if (!is_pow_of_2($a) || ($a < 0) || ($a > $MAXALIGN)) {
        die "bad align() value $a\n";
    }
    $alignment_restriction = $a;
}

sub get_offset()
{
    # Emit code to get a random offset within the memory block, of the
    # right alignment, into r0
    # We require the offset to not be within 256 bytes of either
    # end, to (more than) allow for the worst case data transfer, which is
    # 16 * 64 bit regs
    my $offset = (rand(2048 - 512) + 256) & ~($alignment_restriction - 1);
    return $offset
}

sub reg($@)
{
    my ($base, @trashed) = @_;
    # Now r0 is the address we want to do the access to,
    # so just move it into the basereg
    write_add_ri($base, 1, get_offset());
    if (grep $_ == $base, @trashed) {
        return -1;
    }
    return $base;
}

sub reg_plus_reg($$@)
{
    my ($ra, $rb, @trashed) = @_;

    # addi $ra, r1, 0
    write_add_ri($ra, 1, 0);
    # li $rb, 32
    write_mov_ri($rb, 32);

    return $ra
}

sub reg_plus_imm($$@)
{
    # Handle reg + immediate addressing mode
    my ($base, $imm, @trashed) = @_;

    if ($imm < 0) {
        return $base;
    }

    $imm = -$imm;
    write_add_ri($base, 1, $imm);
 
    # Clear r0 to avoid register compare mismatches
    # when the memory block location differs between machines.
    # write_mov_ri($base, 0);

    if (grep $_ == $base, @trashed) {
        return -1;
    }
    return $base;
}

sub eval_with_fields($$$$$) {
    # Evaluate the given block in an environment with Perl variables
    # set corresponding to the variable fields for the insn.
    # Return the result of the eval; we die with a useful error
    # message in case of syntax error.
    my ($insnname, $insn, $rec, $blockname, $block) = @_;
    my $evalstr = "{ ";
    for my $tuple (@{ $rec->{fields} }) {
        my ($var, $pos, $mask) = @$tuple;
        my $val = ($insn >> $pos) & $mask;
        $evalstr .= "my (\$$var) = $val; ";
    }
    $evalstr .= $block;
    $evalstr .= "}";
    my $v = eval $evalstr;
    if ($@) {
        print "Syntax error detected evaluating $insnname $blockname string:\n$block\n$@";
        exit(1);
    }
    return $v;
}

sub gen_one_insn($$)
{
    # Given an instruction-details array, generate an instruction
    my $constraintfailures = 0;

    INSN: while(1) {
        my ($forcecond, $rec) = @_;
        my $insn = int(rand(0xffffffff));
        my $insnname = $rec->{name};
        my $insnwidth = $rec->{width};
        my $fixedbits = $rec->{fixedbits};
        my $fixedbitmask = $rec->{fixedbitmask};
        my $constraint = $rec->{blocks}{"constraints"};
        my $memblock = $rec->{blocks}{"memory"};

        $insn &= ~$fixedbitmask;
        $insn |= $fixedbits;

        if (defined $constraint) {
            # user-specified constraint: evaluate in an environment
            # with variables set corresponding to the variable fields.
            my $v = eval_with_fields($insnname, $insn, $rec, "constraints", $constraint);
            if (!$v) {
                $constraintfailures++;
                if ($constraintfailures > 10000) {
                    print "10000 consecutive constraint failures for $insnname constraints string:\n$constraint\n";
                    exit (1);
                }
                next INSN;
            }
        }

        # OK, we got a good one
        $constraintfailures = 0;

        my $basereg;

        if (defined $memblock) {
            # This is a load or store. We simply evaluate the block,
            # which is expected to be a call to a function which emits
            # the code to set up the base register and returns the
            # number of the base register.
            # Default alignment requirement for ARM is 4 bytes,
            # we use 16 for Aarch64, although often unnecessary and overkill.
            align(16);
            $basereg = eval_with_fields($insnname, $insn, $rec, "memory", $memblock);
        }

        insn32($insn);

        if (defined $memblock) {
            # Clean up following a memory access instruction:
            # we need to turn the (possibly written-back) basereg
            # into an offset from the base of the memory block,
            # to avoid making register values depend on memory layout.
            # $basereg -1 means the basereg was a target of a load
            # (and so it doesn't contain a memory address after the op)
            if ($basereg != -1) {
                write_mov_ri($basereg, 0);
            }
        }
        return;
    }
}

my $lastprog;
my $proglen;
my $progmax;

sub progress_start($$)
{
    ($proglen, $progmax) = @_;
    $proglen -= 2; # allow for [] chars
    $| = 1;        # disable buffering so we can see the meter...
    print "[" . " " x $proglen . "]\r";
    $lastprog = 0;
}

sub progress_update($)
{
    # update the progress bar with current progress
    my ($done) = @_;
    my $barlen = int($proglen * $done / $progmax);
    if ($barlen != $lastprog) {
        $lastprog = $barlen;
        print "[" . "-" x $barlen . " " x ($proglen - $barlen) . "]\r";
    }
}

sub write_risuop($)
{
    # instr with bits (28:27) == 0 0 are UNALLOCATED
    my ($op) = @_;
    insn32(0x00005af0 | $op);
}

sub progress_end()
{
    print "[" . "-" x $proglen . "]\n";
    $| = 0;
}

sub write_test_code($)
{
    my ($params) = @_;

    my $condprob = $params->{ 'condprob' };
    my $numinsns = $params->{ 'numinsns' };
    my $fp_enabled = $params->{ 'fp_enabled' };
    my $outfile = $params->{ 'outfile' };

    my @pattern_re = @{ $params->{ 'pattern_re' } };
    my @not_pattern_re = @{ $params->{ 'not_pattern_re' } };
    my %insn_details = %{ $params->{ 'details' } };

    open_bin($outfile);

    # convert from probability that insn will be conditional to
    # probability of forcing insn to unconditional
    $condprob = 1 - $condprob;

    # TODO better random number generator?
    srand(0);

    # Get a list of the insn keys which are permitted by the re patterns
    my @keys = sort keys %insn_details;
    if (@pattern_re) {
        my $re = '\b((' . join(')|(',@pattern_re) . '))\b';
        @keys = grep /$re/, @keys;
    }
    # exclude any specifics
    if (@not_pattern_re) {
        my $re = '\b((' . join(')|(',@not_pattern_re) . '))\b';
        @keys = grep !/$re/, @keys;
    }
    if (!@keys) {
        print STDERR "No instruction patterns available! (bad config file or --pattern argument?)\n";
        exit(1);
    }
    print "Generating code using patterns: @keys...\n";
    progress_start(78, $numinsns);

    #if ($fp_enabled) {
    #    write_set_fpscr($fpscr);
    #}

    if (grep { defined($insn_details{$_}->{blocks}->{"memory"}) } @keys) {
        write_memblock_setup();
    }

    # memblock setup doesn't clean its registers, so this must come afterwards.
    write_random_register_data($fp_enabled);

    for my $i (1..$numinsns) {
        my $insn_enc = $keys[int rand (@keys)];
        #dump_insn_details($insn_enc, $insn_details{$insn_enc});
        my $forcecond = (rand() < $condprob) ? 1 : 0;
        gen_one_insn($forcecond, $insn_details{$insn_enc});
        write_risuop($OP_COMPARE);
        # Rewrite the registers periodically. This avoids the tendency
        # for the VFP registers to decay to NaNs and zeroes.
        if ($periodic_reg_random && ($i % 100) == 0) {
            write_random_register_data($fp_enabled);
        }
        progress_update($i);
    }
    write_risuop($OP_TESTEND);
    progress_end();
    close_bin();
}

1;
