#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use Getopt::Std;


my $progNamePrefix = "add-terms-and-types"; 
my $progname = "$progNamePrefix.pl";

my $umlsCUIColNo = 1; # 1-indexed col no for the CUI in MRCONSO.RRF
my $umlsLangColNo = 2; # 1-indexed col no for the language in MRCONSO.RRF
my $umlsIsPrefColNo = 7; # 1-indexed col no for the boolean "is prefered" in MRCONSO.RRF
my $umlsLangFilterVal = "ENG";
my $umlsTermColNo = 15; # 1-indexed col no for the term in MRCONSO.RRF
my $umlsMeshColNo = 12;
my $umlsMeshValue = "MSH";
my $umlsMeshIdColNo = 11;

my $umlsSTYCUIColNo = 1;
my $umlsSTYTypeIdColNo = 2;
my $umlsSTYTypeTreeIdColNo = 3;
my $umlsSTYTypeNameColNo = 4;

my $coarseFileCoarseCol = 1;
my $coarseFileDetailedTypeCol = 3;

my $multipleCUIs = "fail";  # 'fail', 'mesh", 'cuis'


sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "\n"; 
	print $fh "Usage:  $progname [options] <UMLS META dir> <input file> <col no>\n";
	print $fh "\n";
	print $fh "  Prints the list (column) of CUIs corresponding to the Mesh descriptors \n";
	print $fh "   in <col no> from <input file>.\n";
	print $fh "  <col no> can contain a list of columns nos, e.g. '1,3,5'. In this case\n";
	print $fh "   the same number of columns in printed to STDOUT\n";
	print $fh "  Main options:\n";
	print $fh "     -h print this help message.\n";
	print $fh "     -i ignore when the mesh descriptor is not found in UMLS, just print\n";
	print $fh "        the original value instead.\n";
	print $fh "     -m <fail|mesh|cuis> in case a mesh descriptor has Multiple corresponding\n";
	print $fh "        CUIs, either:\n";
	print $fh "          - 'fail' (default)\n";
	print $fh "          - print the orginal 'mesh' descriptor\n";
	print $fh "          - print the list of 'cuis' (Caution: this can cause ambiguity issues)\n";
	print $fh "            this option requires '-l' to provide a separator.\n";
	print $fh "     -l <sep> allows the mesh column to contain a list of mesh descriptors\n";
	print $fh "        separated by <sep>. Each descriptor is converted and the same\n";
	print $fh "        separator is used in the output. An empty list is allowed.\n";
	print $fh "     -M Mesh descriptors in input file with MajorYN indicator, e.g. 'D008955|N;'\n";
	print $fh "        The '|Y' or '|N' is ignored.\n";
	print $fh "     -k keep original columns, i.e. add converted column.\n";
	print $fh "\n";
}




# PARSING OPTIONS
my %opt;
getopts('him:l:kM', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);

usage(*STDOUT) && exit 0 if $opt{h};
print STDERR "3 arguments expected, but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 3);

my $ignoreNotFound = $opt{i};
$multipleCUIs = $opt{m} if (defined($opt{m}));
my $listOfMeshSep = $opt{l};
my $keepColumns = $opt{k};
my $majorYNFormat = $opt{M};

my $umlsDir=$ARGV[0];
my $in= $ARGV[1];
my $colsNos=$ARGV[2];

my @colsNos = split(",", $colsNos);



my $file= "$umlsDir/MRCONSO.RRF";
print STDERR "Reading UMLS '$file'...\n";
open(my $inFH,  "<", $file) or die "cannot open < $file: $!";
my %umlsByMesh;
my $lineNo=0;
while (<$inFH>) {
    chomp;
    my @cols = split(/\|/, $_);
    if ($cols[$umlsLangColNo-1] eq $umlsLangFilterVal) { # filter in English language
	my $mesh = $cols[$umlsMeshIdColNo-1];
	my $cui = $cols[$umlsCUIColNo-1];
	$umlsByMesh{$mesh}->{$cui} = 1 if (length($mesh)>0); 
    }
    $lineNo++;
    if ($lineNo % 65536 == 0) {
	print STDERR "\r line $lineNo ";
    }
}
print STDERR "\n";
close($inFH);



open($inFH,  "<", $in) or die "cannot open < $in: $!";
my %notfound;
while (<$inFH>) {
    chomp;
    my @cols = split("\t",$_,-1);     # -1 limit to include empty field
    my @out;
    foreach my $colNo (@colsNos) {
	my $meshStr = $cols[$colNo-1];
	die "bug" if (!defined($meshStr));
	my @meshDescrs;
	if (defined($listOfMeshSep)) {
	    @meshDescrs = split($listOfMeshSep, $meshStr);
	} else {
	    push(@meshDescrs,$meshStr);
	}
	my @thisColOutput;
	foreach my $mesh0 (@meshDescrs) {
	    my $mesh;
	    if (defined($majorYNFormat)) {
		my $crap;
		($mesh, $crap) = split(/\|/, $mesh0);
	    } else {
		$mesh = $mesh0;
	    }
	    my $cuisHash = $umlsByMesh{$mesh};
	    if (defined($cuisHash)) {
		my @cuis =  keys %$cuisHash;
		if (scalar(@cuis) > 1) {
		    if ($multipleCUIs eq "fail") {
			die "Problem: several CUIs corresponding to MEsh '$mesh': ".join(", ", @cuis) ;
		    } elsif ($multipleCUIs eq "mesh") {
			push(@thisColOutput, $mesh);
		    } elsif ($multipleCUIs eq "cuis") {
			die "Error: must provide -l with option '-m cuis'" if (!defined($listOfMeshSep));
			push(@thisColOutput, @cuis);
		    } else {
			die "invalid value for option '-m'; '$multipleCUIs'.";
		    }
		} else {
		    push(@thisColOutput, @cuis);
		}
	    } else {
		die "Error: no UMLS entry found for Mesh '$mesh'" unless ($ignoreNotFound);
		push(@thisColOutput, $mesh);
		$notfound{$mesh} = 1;
	    }
	}
	if (defined($listOfMeshSep)) {
	    push(@out, join($listOfMeshSep, @thisColOutput));
	} else {
	    push(@out, $thisColOutput[0]);
	}
    }
    if (defined($keepColumns)) {
	unshift(@out,@cols);
    }
    print join("\t", @out)."\n";
}
print STDERR "Values not found in UMLS: ".join(",", keys %notfound) if ($ignoreNotFound);
close($inFH);







