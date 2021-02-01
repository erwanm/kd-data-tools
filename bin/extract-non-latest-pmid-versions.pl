#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use Getopt::Std;

my $progNamePrefix = "extract-non-latest-pmid-versions"; 
my $progname = "$progNamePrefix.pl";

my $pmidColNo=1;
my $versionColNo=3;

sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "\n"; 
	print $fh "Usage: $progname [options] <input file> <output file>\n";
	print $fh "\n";
	print $fh "  <input file> is the output from 'get-mesh-descriptors-by-pmid.py': 'unfiltered-medline.mesh-by-pmid.with-year-journal.tsv'\n";
	print $fh "\n";
	print $fh "\n";
	print $fh "  Main options:\n";
	print $fh "     -h print this help message\n";
	print $fh "\n";
}



# PARSING OPTIONS
my %opt;
getopts('h', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
#$termSep = $opt{s} if (defined($opt{s}));
usage(*STDOUT) && exit 0 if $opt{h};
print STDERR "2 arguments expected, but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 2);


my $inputFile = $ARGV[0];
my $outputFile = $ARGV[1];

my %latest;
my $inFH;
my $f = $inputFile;
my $lineNo=1;
open($inFH,  "<", $f) or die "cannot open < $f: $!";
my $outFH;
$f = $outputFile;
open($outFH, '>', $f) or die "cannot open > '$f': $!";
while (<$inFH>) {
    print STDERR "\r$lineNo   " if ($lineNo % 512 == 0);
    chomp;
    my @cols = split("\t",$_, -1);
    my $pmid = $cols[$pmidColNo-1];
    my $version = $cols[$versionColNo-1];
#    print STDERR "DEBUG $pmid\t$version\n" if ($version ne "1");
    if (defined($latest{$pmid})) {
	my $oldVersion = $latest{$pmid};
#	print STDERR "DEBUG oldVersion=$oldVersion\n";
	if ($oldVersion < $version) {
	    print $outFH "$pmid\t$oldVersion\n";
	    $latest{$pmid} = $version;
	} elsif ($oldVersion > $version) {
	    print $outFH "$pmid\t$version\n";
	} else {
	    die "Error: found identical version $version for pmid $pmid";
	}
    } else {
	$latest{$pmid} = $version;
    }
    $lineNo++;
}
print STDERR "\n";
close($inFH);
close($outFH);


