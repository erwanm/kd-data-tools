#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use Getopt::Std;

my $progNamePrefix = "build-doc-concept-matrix"; 
my $progname = "$progNamePrefix.pl";


my $docLevel = 4;


sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "\n"; 
	print $fh "Usage: $progname [options] <input 'mined' dir> <output dir>\n";
	print $fh "\n";
	print $fh "   Generates a doc-concept matrix using the detailed output from Jake Lever's KD\n";
	print $fh "   system, together with concepts frequencies by document.\n";
	print $fh "     - <input 'mined' dir> is a directory containing the .tok and .cuis data files\n";
	print $fh "       (see also option -m for directly using the KD output dir  'mined')\n";
	print $fh "     - An output file has the following format:\n";
	print $fh "         <year> <doc id> <list of concepts-frequency pairs>\n";
	print $fh "         where:\n";
	print $fh "           - <doc id> identifies the 'document'. It contains the pmid, optionally the\n";
	print $fh "             part id and the sentence id depending on option -d.\n";
	print $fh "           - <list of concepts-frequency pairs> is made of pairs <concept>:<freq>\n";
	print $fh "             separated by spaces.\n";
	print $fh "\n";
	print $fh "  Main options:\n";
	print $fh "     -h print this help message\n";
	print $fh "     -d <level> specify the level of document to consider: 1 for article level, 2 for \n";
	print $fh "        'article part' level, 3 for 'article element' level, and 4 for sentence level.\n";
	print $fh "        Default: $docLevel.\n";
	print $fh "     -m if used, <input 'mined' dir> contains subfolders 'articles' and 'abstracts'\n";
	print $fh "        and the data is read from there (use this to use KD output dir directly).\n";
	print $fh "     -r <reference file> use this reference file for converting the indexes in the\n";
	print $fh "        data files to actual CUIs. Typically <reference file> is\n";
	print $fh "        'umlsWordlist.WithIDs.txt'. A terms id corresponds to the line number\n";
	print $fh "        containing the CUI in the reference file.\n";
	print $fh "     -o Print the output to a single file (<output dir> is interpreted as a file)\n";
	print $fh "     -i Read a single .cuis file as input instead of <input 'mined' dir>\n";
	print $fh "     -u include only unambiguous concepts, i.e. ignore any term which corresponds to\n";
	print $fh "        more than one CUI.\n";
	print $fh "     -e <file:colPMID:colCUIs:sep> external resource providing additional CUIs for\n";
	print $fh "        every document by PMID, , e.g. list of converted Mesh descriptors.\n";
	print $fh "        This option makes more sense with '-d 1' (article level), if used with other\n";
	print $fh "        levels the doc-level CUIs are added for every part/element/sentence.\n";
}


sub keyDependingOnDocLevel {
    my ($pmidDotUniq,$docType,$docId,$sentNo) = @_;


    my $key = $pmidDotUniq;
    if ($docLevel > 1) {
	$key .= ",".$docType;
	if ($docLevel > 2) {
	    $key .= ",".$docId;
	    if ($docLevel > 3) {
		$key .= ",".$sentNo;
	    }
	}
    }
    return $key;
}



# PARSING OPTIONS
my %opt;
getopts('hr:moid:ue:', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
#$termSep = $opt{s} if (defined($opt{s}));
usage(*STDOUT) && exit 0 if $opt{h};
print STDERR "2 arguments expected, but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 2);

my $cuiRefFile = $opt{r};
my $originalMinedFormat = $opt{m};
my $outputAsFile = $opt{o};
my $inputAsFile = $opt{i};
$docLevel = $opt{d} if (defined($opt{d}));
my $unambigOnly = defined($opt{u});
my $externalCuisByPMIDArg = $opt{e};
my $minedDir = $ARGV[0];
my $outputDir = $ARGV[1];


my $outFH;
if ($outputAsFile) {
    my $f = $outputDir;
    open($outFH, '>', "$f") or die "cannot open '$f': $!";
} else {
    if (! -d $outputDir) {
	mkdir $outputDir or die "cannot create dir $outputDir: $!";
    }
}

my @dataFiles;
if ($inputAsFile) {
    # the input is a single .cuis file given instead of '$minedDir'
    push(@dataFiles, "$minedDir");
} else {
    if ($originalMinedFormat) {
	@dataFiles = glob("$minedDir/*/*.cuis");
    } else {
	@dataFiles = glob("$minedDir/*.cuis");
    }
}
die "Error: zero input document to process" if (scalar(@dataFiles)==0);


my %idToCUI;
if (defined($cuiRefFile)) {
    open(my $inFH,  "<", $cuiRefFile) or die "cannot open < $cuiRefFile: $!";
    my $id=0;
    print "Reading reference file '$cuiRefFile'...\n";
    while (<$inFH>) {
	chomp;
	my @cols =split("\t",$_);
	my $cui = $cols[0];
	$idToCUI{$id} = $cui;
	$id++;
    }
    close($inFH);
}


my %externalCuisByPMID;
if (defined($externalCuisByPMIDArg)) {
    my ($f, $pmidCol, $cuisCol, $sep) = split(":", $externalCuisByPMIDArg);
    die "Incorrect format in arg for -e, must be 'file:colPMID:colCUIs:sep'" if (!defined($sep));
    open(my $inFH,  "<", $f) or die "cannot open < $f: $!";
    print "Reading external CUIs by PMID resource file '$f'...\n";
    while (<$inFH>) {
	chomp;
	my @cols =split("\t",$_,-1);
	my $pmid = $cols[$pmidCol-1];
	my $cuisStr = $cols[$cuisCol-1];
	my $cuis;
	@$cuis = split($sep, $cuisStr);
	print STDERR "Warning: PMID $pmid defined twice in $f, overwriting" if (defined($externalCuisByPMID{$pmid}));
	$externalCuisByPMID{$pmid} = $cuis;
    }
    close($inFH);
}



my $externCuisByPMIDFound = 0;
my $nbEntries = 0;
my $nbFiles=scalar(@dataFiles);
for (my $fileNo=0; $fileNo<$nbFiles; $fileNo++) {
    my $dataFile = $dataFiles[$fileNo];
    open(my $inFH,  "<", $dataFile) or die "cannot open < $dataFile: $!";
    print "\rReading data file '$dataFile' [".($fileNo+1)."/$nbFiles] ...";
    my ($baseFileId) = ($dataFile =~ m:([^/]*).out.cuis$:);
    die "Bug regex" if (!defined($baseFileId));
    my %selected;
    while (<$inFH>) {
	$nbEntries++;
	chomp;
	my @cols =split("\t",$_);
	die "data format error: expecting 7 columns $!" if (scalar(@cols) != 7);
	my @cuisOrIds = split(",", $cols[4]);

	if (!$unambigOnly || (scalar(@cuisOrIds)==1)) {
	    if (defined($cuiRefFile)) { 
		@cuisOrIds = map { $idToCUI{$_} }  @cuisOrIds;
	    }
	    my $pmidDotUniq = $cols[0];
	    my $docType = $cols[1];
	    my $docId = $cols[2];
	    my $sentNo = $cols[3];
	    my $pos = $cols[5];
	    my $length = $cols[6];
	    my $docKey = keyDependingOnDocLevel($pmidDotUniq,$docType,$docId,$sentNo);
#	print STDERR "DEBUG: key '$docKey', adding: ".join(",",@cuisOrIds)."\n";
	    foreach my $cuiOrId (@cuisOrIds) {
		$selected{$docKey}->{$cuiOrId}++;
	    }
	    if (defined($externalCuisByPMIDArg)) {
		my $pmid = "NOPMID";
		if ($pmidDotUniq !~ m/^NOPMID/) {
		    ($pmid) = ( $pmidDotUniq =~ m/^([0-9]+)/); # we need the pmid in case of filtering by pmid
		    die "bug" if (!defined($pmid));
		}
		my $externCuis = $externalCuisByPMID{$pmid};
		if ($externCuis) {
		    foreach my $cui (@$externCuis) {
			$selected{$docKey}->{$cui}++;
		    }
		    $externCuisByPMIDFound++;
		}
	    }
	}	
    }    
    
    

    if (scalar(keys %selected) > 0) {

	# reading tok file only to get the year
	my ($basePath) =  ($dataFile =~ m/^(.*).cuis$/g);
	my $tokFile = "$basePath.tok";
	open($inFH,  "<", $tokFile) or die "cannot open < $tokFile: $!";
#	print "\rReading tok data file '$tokFile'...             ";
	my %yearByKey;
	while (<$inFH>) {
	    chomp;
	    my @cols =split("\t",$_);
	    my $pmid0 = $cols[0];
	    my $year = $cols[1];
	    my $docType = $cols[2];
	    my $docId = $cols[3];
	    my $sentNo = $cols[4];
	    my $docKey = keyDependingOnDocLevel($pmid0,$docType,$docId,$sentNo);
#	    print STDERR "DEBUG2: searching key '$docKey'\n";
	    if (defined($selected{$docKey})) {
		$yearByKey{$docKey} = $year;
	    }
	}

	if (!$outputAsFile) {
	    my ($base) = ($basePath =~ m:/([^/]+)$:);
#	    print STDERR "DEBUG basePath='$basePath', output base='$base'\n";
	    my $f = "$outputDir/$base.out"; 
	    open($outFH, '>', "$f") or die "cannot open '$f': $!";
	}
	foreach my $docKey (sort keys %selected) {
	    my $year = $yearByKey{$docKey};
	    # in the articles data we add a 'unique id' to the pmid: <pmid>.<unique id>
	    # but this is unique only to the KD file so we prefix the pmid with the base filename
	    print $outFH "$year\t$baseFileId,$docKey\t";
	    my @conceptsList;
	    while (my($cui, $freq) = each %{$selected{$docKey}}) {
		push(@conceptsList, "$cui:$freq");
	    }
	    print $outFH join(" ",@conceptsList)."\n";
	}
	close($outFH) if (!$outputAsFile);

    }

}

print "\n";


print "$nbEntries processed\n";
print "External CUIs by PMID: additional CUIs found for $externCuisByPMIDFound entries (".($externCuisByPMIDFound/$nbEntries*100)." %).\n" if (defined($externalCuisByPMIDArg));

