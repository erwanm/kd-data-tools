#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use Getopt::Std;

my $progNamePrefix = "calculate-idf"; 
my $progname = "$progNamePrefix.pl";

my $freqSep=':';
my $pairsSep=' ';
my $header = 1;



sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "\n"; 
	print $fh "Usage: $progname [options] <doc-concept matrix file> <concepts column no> <output file>\n";
	print $fh "\n";
	print $fh "   Computes the joint frequency, PMI and (possibly) other statistics for every pair of\n";
	print $fh "    concepts in <doc-concept matrix file>, which contains a column <concepts column no>\n";
	print $fh "    made of pairs <concept>:<freq> separated by spaces. The output format is:\n";
	print $fh "      <concept1> <concept2> <joint freq> <c1 freq> <c2 freq> <P(C1)> <P(C2)> <P(C1,C2)> <P(c1/c2)> <P(c2/c1)> <PMI>\n";
	print $fh "\n";
	print $fh "  Main options:\n";
	print $fh "     -h print this help message\n";
#	print $fh "     -t <freq threshold> minimum frequency for a concept to be taken into account.\n";
	print $fh "     -S <pairs separator> instead of '$pairsSep'\n";
	print $fh "     -s <freq separator> instead of '$freqSep'\n";
#	print $fh "     -m mesh: don't use <freq> value, count each descriptor as one.\n";
	print $fh "     -H no header (default: yes)\n";
	print $fh "     -g <group file> additionally to individual concepts, compute stats between these\n";
	print $fh "        groups of concepts and any other concept (individual or group). <group file>\n";
	print $fh "         describes a group of concepts by line as follows: \n";
	print $fh "           <group name> <list of space-separated concepts>\n";
	print $fh "     -n no sorting of the pairs by decreasing joint frequency (default) (more efficient).\n";
	print $fh "\n";
}

# returns pair MI and PMI of the postive case A and B
#
sub binaryMutualInformation {
    my ($pA, $pB, $pJoint) = @_;

    my $pnAB = $pB - $pJoint;
    my $pAnB = $pA - $pJoint;
    my $pnAnB = 1 - ($pJoint + $pnAB + $pAnB);

    my $pmi;
    my $mi = 0;

    if ($pnAnB>0) {
	$pmi = log( $pnAnB / ( (1-$pA) * (1-$pB) ) ) / log(2) ;
	$mi += $pnAnB * $pmi;
    }
    if ($pnAB>0) {
	$pmi = log( $pnAB /  ( (1-$pA) *  $pB    ) ) / log(2);
	$mi += $pnAB * $pmi;
    }
    if ($pAnB>0) {
	$pmi = log( $pAnB /  (  $pA    * (1-$pB) ) ) / log(2);
	$mi += $pAnB * $pmi;
    }
    $pmi = log( $pJoint / ( $pA    *  $pB    ) ) / log(2);
    $mi += $pJoint * $pmi;

    return ($mi, $pmi);
}


sub printPairResult {

    my ($FH, $pair, $uniFreq, $jointFreq, $nbDocs) = @_;
    my ($c1, $c2) = split("\t", $pair);
    my $freqC1 = $uniFreq->{$c1};
    my $freqC2 = $uniFreq->{$c2};
    my $probC1 = $freqC1 / $nbDocs;
    my $probC2 = $freqC2 / $nbDocs;
    my $joint = $jointFreq->{$pair};
    my $jointP = $joint / $nbDocs;
    my $C1GivenC2 = $joint / $freqC2;
    my $C2GivenC1 = $joint / $freqC1;
    my ($mi, $pmi) = binaryMutualInformation($probC1, $probC2, $jointP);
    print $FH "$c1\t$c2\t$freqC1\t$freqC2\t$probC1\t$probC2\t$joint\t$jointP\t$C1GivenC2\t$C2GivenC1\t$pmi\t$mi\n";

}


# PARSING OPTIONS
my %opt;
getopts('hs:S:mHg:n', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
#$termSep = $opt{s} if (defined($opt{s}));
usage(*STDOUT) && exit 0 if $opt{h};
print STDERR "3 arguments expected, but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 3);

$freqSep = $opt{s} if (defined($opt{s}));
$pairsSep = $opt{S} if (defined($opt{S}));
my $dontUseFreq = defined($opt{m});
$header = 0 if (defined($opt{H}));
my $groupFile = $opt{g};
my $sorting = defined($opt{n}) ? 0 : 1;

my $input = $ARGV[0];
my $conceptsColNo = $ARGV[1];
my $outputFile = $ARGV[2];


my %groups;
if (defined($groupFile)) {
    my $f = $groupFile;
    print STDERR "Reading group file $f ...\n";
    open(my $inFH,  "<", $f) or die "cannot open < '$f': $!";
    while (<$inFH>) {
	chomp;
	my @cols =split("\t",$_);
	my $name = $cols[0];
	my @concepts = split(" ", $cols[1]);
	foreach my $c (@concepts) {
	    $groups{$c}->{$name} = 1;
	}
    }
}


my %jointFreq;
my %uniFreq;
my $nbDocs;
open(my $inFH,  "<", $input) or die "cannot open < '$input': $!";
while (<$inFH>) {
    $nbDocs++;
    print STDERR "\rReading doc $nbDocs ...";
    chomp;
    my @cols =split("\t",$_);
    my $conceptsStr = $cols[$conceptsColNo-1];
    if (defined($conceptsStr) && (length($conceptsStr)>0)) {
	my @concepts = split($pairsSep, $conceptsStr);
	if (defined($groupFile)) {
	    my %groupsThis;
	    foreach my $c1Str (@concepts) {
		my @parts1 = split($freqSep, $c1Str);
		my $c1 = $parts1[0];
		my $h = $groups{$c1};
		if (defined($h)) {
		    foreach (keys %$h) {
			$groupsThis{$_} = 1;
#			print STDERR "DEBUG FOUND $_ for $c1\n";
		    }
		}
	    }
	    push(@concepts, keys %groupsThis);
#	    print STDERR "DEBUG: ".join(",",@concepts)."\n";
	}
	foreach my $c1Str (@concepts) {
#	    print STDERR "DEBUG $c1Str\n";
	    my @parts1 = split($freqSep, $c1Str);
	    my $c1 = $parts1[0];
	    $uniFreq{$c1}++;
	    foreach my $c2Str (@concepts) {
#		print STDERR "  DEBUG $c2Str\n";
		my @parts2 = split($freqSep, $c2Str);
		my $c2 = $parts2[0];
		if ($c1 lt $c2) {
		    $jointFreq{$c1."\t".$c2}++;
		}
	    }
	}
    }
}
close($inFH);
print STDERR "\n";

my $nbPairs=scalar(keys %jointFreq);
my @sorted;
if ($sorting) {
    print STDERR scalar(keys %jointFreq)." pairs found. Sorting...\n";
    @sorted = sort { $jointFreq{$b} <=> $jointFreq{$a} || $a cmp $b } (keys %jointFreq);
}

my $pairNo=1;
my $f = $outputFile;
open(my $outFH, '>', "$f") or die "cannot open > '$f': $!";
print $outFH "C1\tC2\tfreqC1\tfreqC2\tprobC1\tprobC2\tfreqJoint\tprobJoint\tprobC1GivenC2\tprobC2GivenC1\tPMI\tbinaryMI\n" if ($header);

if ($sorting) {
    for my $pair (@sorted) {
	print STDERR "\r pair $pairNo / $nbPairs...";
	printPairResult($outFH, $pair, \%uniFreq, \%jointFreq,$nbDocs);
	$pairNo++;
    }
} else {
    for my $pair (keys %jointFreq) {
	print STDERR "\r pair $pairNo / $nbPairs...";
	printPairResult($outFH, $pair, \%uniFreq, \%jointFreq,$nbDocs);
	$pairNo++;
    }
}
close($outFH);
print STDERR "\n";



