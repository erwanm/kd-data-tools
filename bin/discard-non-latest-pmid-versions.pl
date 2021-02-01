#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use Getopt::Std;

my $progNamePrefix = "discard-non-latest-pmid-versions"; 
my $progname = "$progNamePrefix.pl";

my $pmidColNo=1;
my $versionColNo;

sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "\n"; 
	print $fh "Usage: ls <files> | $progname [options] <non-latest pmid versions file> <output dir>\n";
	print $fh "\n";
	print $fh "  Deduplicates KD Medline abstracts output based on the PMID version.\n";
	print $fh "  <non-latest pmid versions file> is the output from 'extract-non-latest-pmid-versions'\n";
	print $fh "  <input file> is any of the KD output files: .raw, .tok or .cuis\n";
	print $fh "  Both the pmid and version number are supposed to be given in the first column as:\n";
	print $fh "  <pmid>.<version>.\n";
	print $fh "\n";
	print $fh "  Main options:\n";
	print $fh "     -h print this help message\n";
	print $fh "     -c <version col no> specify a different column no for the version. The version\n";
	print $fh "        column is also removed from the output.\n";
	print $fh "\n";
}



# PARSING OPTIONS
my %opt;
getopts('hc:', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
#$termSep = $opt{s} if (defined($opt{s}));
usage(*STDOUT) && exit 0 if $opt{h};
print STDERR "2 arguments expected, but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 2);

$versionColNo = $opt{c} if (defined($opt{c}));
my $nonLatestFile = $ARGV[0];
my $outputDir = $ARGV[1];


my @dataFiles;
while (<STDIN>) {
    chomp;
    push(@dataFiles, $_);
}


my %nonLatest;
my $inFH;
my $f = $nonLatestFile;
open($inFH,  "<", $f) or die "cannot open < $f: $!";
while (<$inFH>) {
    chomp;
    my @cols = split("\t",$_, -1);
    $nonLatest{$cols[0].".".$cols[1]} = 1;
}
close($inFH);


if (! -d $outputDir) {
    mkdir $outputDir or die "cannot create dir $outputDir: $!";
}

my $discarded=0;
for (my $fileNo=0; $fileNo<scalar(@dataFiles); $fileNo++) {
    print STDERR "\rFile ".($fileNo+1)." / ".scalar(@dataFiles)."  ";
    my ($base) = ($dataFiles[$fileNo] =~ m:([^/]+)$:);
    $f = $dataFiles[$fileNo];
#    print STDERR "$f\n";
    open($inFH,  "<", $f) or die "cannot open < $f: $!";
    $f = "$outputDir/$base";
    open(my $outFH, '>', "$f") or die "cannot open > '$f': $!";
    while (<$inFH>) {
	chomp;
	my @cols = split("\t",$_, -1);
	my $pmidDotVersion = $cols[$pmidColNo-1];
	if (defined($versionColNo)) {
	    $pmidDotVersion .= ".".$cols[$versionColNo-1];
	    splice(@cols, $versionColNo-1, 1);
	}
	if (defined($nonLatest{$pmidDotVersion})) {
	    $discarded++;
	} else {
	    my ($pmid, $version) = split ('\.', $pmidDotVersion);
	    $cols[$pmidColNo-1] = $pmid;
	    print $outFH join("\t", @cols)."\n";
	}
    }
    close($inFH);
    close($outFH);
}

print STDERR "\nDiscarded lines: $discarded\n";
