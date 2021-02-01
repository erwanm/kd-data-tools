#!/usr/bin/perl

use strict;
use warnings;
use Carp;
use Getopt::Std;

my $progNamePrefix = "disambiguation-for-KD-output"; 
my $progname = "$progNamePrefix.pl";

my $cuiRefFile;
my %idToCUI;

my $method0 = "advanced";


my $minConceptFreq0 = 3;
my $minPosteriorProb0 = 0.95;
my $ignoreTargetIfNotInPairsData = 0;

my $totalNbDocs;
my %uniFreq;
my %jointFreq;

my $totalCases = 0;
my $totalAmbig = 0;
my $ambigFixed = 0;
my $uniqueTotalCases = 0;
my $uniqueSuccess = 0;
my $uniqueUnknownTarget = 0;
my $uniqueMethodNA = 0;
my $uniqueThrehsholdReject = 0;

my $advancedDiscriminativeFeatsOnly = 1;

sub usage {
	my $fh = shift;
	$fh = *STDOUT if (!defined $fh);
	print $fh "\n"; 
	print $fh "Usage: $progname [options] <input 'mined' dir> <nb docs> <pairs stats file> <output dir>\n";
	print $fh "\n";
	print $fh "   TODO\n";
	print $fh "\n";
	print $fh "\n";
	print $fh "  Main options:\n";
	print $fh "     -h print this help message\n";
	print $fh "     -m if used, <input 'mined' dir> contains subfolders 'articles' and 'abstracts'\n";
	print $fh "        and the data is read from there (use this to use KD output dir directly).\n";
	print $fh "     -r <reference file> use this reference file for converting the indexes in the\n";
	print $fh "        data files to actual CUIs. Typically <reference file> is\n";
	print $fh "        'umlsWordlist.WithIDs.txt'. A terms id corresponds to the line number\n";
	print $fh "        containing the CUI in the reference file.\n";
	print $fh "     -i Read a single .cuis file as input instead of <input 'mined' dir>\n";
	print $fh "     -f <min freq> min frequency of concept. Default: $minConceptFreq0.\n";
	print $fh "     -b <min posterior prob> min posterior NB prob for 'accepting' the predicted\n";
	print $fh "        disambiguated concept. Default: $minPosteriorProb0.\n";
	print $fh "     -a <method> where method is 'basic', 'NB', 'advanced'. Default: '$method0'.\n";
	print $fh "     -d dismiss potential target if it has zero occurrences in the pairs data\n";
	print $fh "        (only for methods NB and advanced). CAUTION: this can cause errors.\n";
	print $fh "     -A use all features instead of 'discriminative features' only for the advanced\n";
	print $fh "        method. Unused with other methods.\n";
	print $fh "     -M multi methods: allows a list of values for -a, -f, -b and runs the process\n";
	print $fh "        for every combination of parameters values. Values separated by ':'.\n";
	print $fh "        This option is intended to reduce computation time due to loading\n";
	print $fh "        <pairs stats file> multiple times in case of testing the different methods.\n";
}



sub resetStats {
    $totalCases = 0;
    $totalAmbig = 0;
    $ambigFixed = 0;
    $uniqueTotalCases = 0;
    $uniqueSuccess = 0;
    $uniqueUnknownTarget = 0;
    $uniqueMethodNA = 0;
    $uniqueThrehsholdReject = 0;
}



sub disambiguateBasic {
    my ($targets, $inputFeatures, $minConceptFreq, $minPosteriorProb) = @_;

#    print STDERR "DEBUG targets = ".join(";", @$targets)."\n";
#   print STDERR "DEBUG inputFeatures = ".join(";", keys %$inputFeatures)."\n";
    $uniqueTotalCases++;
    my $singlePresent = undef;
    # performing "disambiguation", i.e. checking which cuis appear individually for every ambiguous group of cuis
    foreach my $id (@$targets) {
	push(@$singlePresent, $id) if  (defined($inputFeatures->{$id}));
    }
    if (defined($singlePresent)) {
	$uniqueSuccess++ ;
    } else {
	$uniqueMethodNA++;
    }
    return $singlePresent;

}


sub disambiguateNB {
    my ($targets, $inputFeatures, $minConceptFreq, $minPosteriorProb) = @_;
    
    $uniqueTotalCases++;
    my %uni;
    my %featuresCuis;
    my %pTargetGivenDoc;
    my @selectedTargets;
    foreach my $target (@$targets) {
	$uni{$target} = $uniFreq{$target};
	if (defined($uni{$target}) && ($uni{$target} >= $minConceptFreq)) {
	    while (my ($cui, $freq) = each (%{$jointFreq{$target}})) {
		if ($uniFreq{$cui}>=$minConceptFreq) {
		    $featuresCuis{$cui}->{$target} = $freq;
		}
	    }
	    $pTargetGivenDoc{$target} = $uni{$target} / $totalNbDocs ; # p(C)
	    push(@selectedTargets, $target);
	} else {
	    # note: if the target is not defined but $ignoreTargetIfNotInPairsData is true,
	    #       the target is skipped but the process continues with the other targets.
	    if (!$ignoreTargetIfNotInPairsData) {
		$uniqueUnknownTarget++;
		return undef;
	    }
	}
    }
    if (scalar(@selectedTargets)==0) { # possible if $ignoreTargetIfNotInPairsData is true,
	$uniqueUnknownTarget++;
	return undef;
    }
    while (my ($featureCui, $jointFreqFeatureByTarget) = each (%featuresCuis)) {
	foreach my $target (@selectedTargets) {
	    my $jointFreqCuiTarget = defined($jointFreqFeatureByTarget->{$target}) ? $jointFreqFeatureByTarget->{$target} : 0 ;
	    my $pFeatGivenTarget = $jointFreqCuiTarget / $uni{$target} ;
	    if (defined($inputFeatures->{$featureCui})) {
		$pTargetGivenDoc{$target} *= $pFeatGivenTarget ; # * p(Xi|C)
	    } else {
		$pTargetGivenDoc{$target} *= (1-$pFeatGivenTarget) ; # * p(Xi|C)
	    }
	}
    }
    my $marginal = 0;
    foreach my $target (@selectedTargets) {
	$marginal += $pTargetGivenDoc{$target};
    }
    if ($marginal == 0) {
	$uniqueMethodNA++;
	return undef;
    } else {
	my $maxTarget;
#	print STDERR "DEBUG RESULTS... marginal = $marginal\n";
	foreach my $target (@selectedTargets) {
	    $pTargetGivenDoc{$target} /= $marginal;
	    $maxTarget = $target if (!defined($maxTarget) || ($pTargetGivenDoc{$maxTarget} < $pTargetGivenDoc{$target}));
#	    print STDERR "   target=$target, prob=$pTargetGivenDoc{$target}\n";
	}
#	if ($totalAmbig>10) {
#	    die "EXIT";
#	}
	if ($pTargetGivenDoc{$maxTarget} >= $minPosteriorProb) {
	    $uniqueSuccess++;
	    return [ $maxTarget ];
	} else {
	    $uniqueThrehsholdReject++;
	    return undef;
	}

    }
}



sub disambiguateAdvanced {
    my ($targets, $inputFeatures, $minConceptFreq, $minPosteriorProb) = @_;

    $uniqueTotalCases++;
    my %uni;
    my %featuresCuis;
    my %countMatches;
    my @selectedTargets;
    foreach my $target (@$targets) {
	$countMatches{$target} = 0;
	$uni{$target} = $uniFreq{$target};
	if (defined($uni{$target}) && ($uni{$target} >= $minConceptFreq)) {
	    while (my ($cui, $freq) = each (%{$jointFreq{$target}})) {
		if (defined($inputFeatures->{$cui}) && ($uniFreq{$cui}>=$minConceptFreq)) {
		    $featuresCuis{$cui}->{$target} = $freq 
		}
	    }
	    push(@selectedTargets, $target);
	} else {
	    # note: if the target is not defined but $ignoreTargetIfNotInPairsData is true,
	    #       the target is skipped but the process continues with the other targets.
	    if (!$ignoreTargetIfNotInPairsData) {
		$uniqueUnknownTarget++;
		return undef;
	    }
	}
    }
    if (scalar(@selectedTargets)==0) { # possible if $ignoreTargetIfNotInPairsData is true,
	$uniqueUnknownTarget++;
	return undef;
    }

    my $totalMatches = 0;
    foreach my $featCUI (keys %$inputFeatures) {
	my $featFreq = $inputFeatures->{$featCUI};
	my %thisFeatCountByTarget;
	foreach my $target (@selectedTargets) {
	    $thisFeatCountByTarget{$target} += $featFreq if (defined($featuresCuis{$featCUI}->{$target}));
	}
	if (!$advancedDiscriminativeFeatsOnly || (scalar(keys %thisFeatCountByTarget) ==1)) { # 
	    foreach my $target (keys %thisFeatCountByTarget) {
		$countMatches{$target} += $thisFeatCountByTarget{$target};
		$totalMatches += $thisFeatCountByTarget{$target};
#		print STDERR "DEBUG   target=$target, featFreq=$featFreq, count=$countMatches{$target}, totalMatches=$totalMatches\n";
	    }
	}	
    }
    if ($totalMatches == 0) {
	$uniqueMethodNA++;
	return undef;
    } else {
	my $maxTarget;
#	print STDERR "DEBUG RESULTS... totalMatches = $totalMatches\n";
	foreach my $target (@selectedTargets) {
#	    print STDERR "DEBUG   target=$target, count=$countMatches{$target}\n";
	    $countMatches{$target} /= $totalMatches;
	    $maxTarget = $target if (!defined($maxTarget) || ($countMatches{$maxTarget} < $countMatches{$target}));
#	    print STDERR "DEBUG   target=$target, prob=$countMatches{$target}\n";
	}
	if ($countMatches{$maxTarget} >= $minPosteriorProb) {
	    $uniqueSuccess++;
	    return [ $maxTarget ];
	} else {
	    $uniqueThrehsholdReject++;
	    return undef;
	}
    }
}



sub processOneDoc {
    my ($pmidDotUniq, $outFH, $data, $method, $minConceptFreq, $minPosteriorProb) = @_;

    # collecting ambiguous/non-ambiguous cases
    my %multi;
    my %single;
    my %countSingle;
    my %oldMulti;
    foreach my $docKey (keys %$data) {
	my $cuisOrIdsStr = $data->{$docKey};
	# print STDERR "    $cuisOrIdsStr\n";
	my $cuisOrIds;
	@$cuisOrIds = split(",", $cuisOrIdsStr);
	if (defined($cuiRefFile)) { 
	    @$cuisOrIds = map { $idToCUI{$_} }  @$cuisOrIds;
	}
	if (scalar(@$cuisOrIds) > 1) {
	    $multi{$cuisOrIdsStr} = $cuisOrIds;
	    $oldMulti{$cuisOrIdsStr} = join(",", sort @$cuisOrIds);
	} else {
	    $single{$cuisOrIdsStr} = $cuisOrIds->[0];
	    $countSingle{$cuisOrIds->[0]}++;
	}
    }

    my %disamb;
    foreach my $cuisOrIdsStr (keys %multi) {
	my $cuis = $multi{$cuisOrIdsStr};
	if ($method eq "basic") {
	    $disamb{$cuisOrIdsStr} =  disambiguateBasic($cuis, \%countSingle, $minConceptFreq, $minPosteriorProb);
	} elsif ($method eq "NB") {
	    $disamb{$cuisOrIdsStr} =  disambiguateNB($cuis, \%countSingle, $minConceptFreq, $minPosteriorProb);
	} elsif ($method eq "advanced") {
	    $disamb{$cuisOrIdsStr} =  disambiguateAdvanced($cuis, \%countSingle, $minConceptFreq, $minPosteriorProb);
	}
    }

    foreach my $docKey (sort keys %$data) {
	my ($docType, $docId, $sentNo, $pos, $length) = split(",", $docKey);
	my $cuisOrIdsStr = $data->{$docKey};
	my $newIdsStr;
	$totalCases++;
	my $cuisOrIds = $multi{$cuisOrIdsStr};
	if (defined($cuisOrIds)) { # ambiguous
	    $totalAmbig++;
	    my $newIds = $disamb{$cuisOrIdsStr};
	    if (defined($newIds)) { # ambiguous case fixed
		$ambigFixed++;
		$newIdsStr = join(",", @$newIds);
	    } else {
		$newIdsStr = $oldMulti{$cuisOrIdsStr};
	    }
	} else {
	    $newIdsStr = $single{$cuisOrIdsStr};
	}
	print $outFH "$pmidDotUniq\t$docType\t$docId\t$sentNo\t$newIdsStr\t$pos\t$length";
    }

}



# PARSING OPTIONS
my %opt;
getopts('hr:mif:b:a:dAM', \%opt ) or  ( print STDERR "Error in options" &&  usage(*STDERR) && exit 1);
#$termSep = $opt{s} if (defined($opt{s}));
usage(*STDOUT) && exit 0 if $opt{h};
print STDERR "5 arguments expected, but ".scalar(@ARGV)." found: ".join(" ; ", @ARGV)  && usage(*STDERR) && exit 1 if (scalar(@ARGV) != 4);

$cuiRefFile = $opt{r};
my $originalMinedFormat = $opt{m};
my $inputAsFile = $opt{i};
$minConceptFreq0 = $opt{f} if (defined($opt{f}));
$minPosteriorProb0 = $opt{b} if (defined($opt{b}));
$method0 = $opt{a} if (defined($opt{a}));
$ignoreTargetIfNotInPairsData = 1 if (defined($opt{d}));
$advancedDiscriminativeFeatsOnly = 0 if (defined($opt{A}));
my $multiParameterValues = $opt{M};

my $minedDir = $ARGV[0];
$totalNbDocs = $ARGV[1];
my $pairStatsFile = $ARGV[2];
my $outputDir = $ARGV[3];


my @multiMethods = split(":", $method0) ;
my @multiMinConceptFreq = split(":", $minConceptFreq0);
my @multiMinPosteriorProb = split(":", $minPosteriorProb0);
my @sortedFreq = sort { $a <=> $b } @multiMinConceptFreq;
my $minMinConceptFreq = $sortedFreq[0];
#print STDERR "DEBUG MIN=$minMinConceptFreq\n";


die "Error: must use -M" if (!defined($multiParameterValues) && ( (scalar(@multiMethods)!=1) || (scalar(@multiMinConceptFreq) != 1) || (scalar(@multiMinPosteriorProb) != 1)  ));


mkdir $outputDir or die "cannot create dir $outputDir: $!"     if (! -d $outputDir);



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

if (defined($multiParameterValues) || ($method0 eq "NB") || ($method0 eq "advanced")) {
    my $f = $pairStatsFile;
    open(my $inFH,  "<", $f) or die "cannot open < $f: $!";
    print STDERR "Reading pairs stats file '$f'...\n";
    my $header=<$inFH>; # skip header
    my $lineNo=1;
    while (<$inFH>) {
	print STDERR "\rline $lineNo   " if ($lineNo % 4096 == 0);	
	chomp;
	my @cols =split("\t",$_);
	my $cui1 = $cols[0];
	my $cui2 = $cols[1];
	my $freqC1 = $cols[2];
	my $freqC2 = $cols[3];
	if (($freqC1 >= $minMinConceptFreq) && ($freqC2 >= $minMinConceptFreq)) {
	    my $jointFreq = $cols[6];
	    die "Error: inconsistent frequency for $cui1" if (defined($uniFreq{$cui1}) && ($uniFreq{$cui1} != $freqC1));
	    die "Error: inconsistent frequency for $cui2" if (defined($uniFreq{$cui2}) && ($uniFreq{$cui2} != $freqC2));
	    $uniFreq{$cui1} = $freqC1;
	    $uniFreq{$cui2} = $freqC2;
	    $jointFreq{$cui1}->{$cui2} = $jointFreq;
	    $jointFreq{$cui2}->{$cui1} = $jointFreq;
	}
	$lineNo++;
    }
    print STDERR "\n";
    close($inFH);
}

foreach my $method (@multiMethods) {
    foreach my $minConceptFreq (@multiMinConceptFreq) {
	foreach my $minPosteriorProb (@multiMinPosteriorProb) {
	    print STDERR "Processing method=$method; minConceptFreq=$minConceptFreq; minPosteriorProb=$minPosteriorProb...\n";
	    resetStats();
	    my $thisOutputDir;
	    if (defined($multiParameterValues))  {
		$thisOutputDir = $outputDir."/${method}_${minConceptFreq}_${minPosteriorProb}";
		mkdir $thisOutputDir or die "cannot create dir $thisOutputDir: $!"     if (! -d $thisOutputDir);
	    } else {
		$thisOutputDir = $outputDir;
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


	    my $nbFiles=scalar(@dataFiles);
	    for (my $fileNo=0; $fileNo<$nbFiles; $fileNo++) {

		my $dataFile = $dataFiles[$fileNo];
		open(my $inFH,  "<", $dataFile) or die "cannot open < $dataFile: $!";
		print "\rReading data file '$dataFile' [".($fileNo+1)."/$nbFiles] ...";

		my ($baseFile) = ($dataFile =~ m:([^/]*.out.cuis)$:);
		die "Bug regex. dataFile='$dataFile'" if (!defined($baseFile));
		my $f = "$thisOutputDir/$baseFile"; 
		open(my $outFH, '>', "$f") or die "cannot open '$f': $!";

		my $dataOneDoc = {};
		my $lastPmid;
		while (<$inFH>) {
		    chomp;
		    my @cols =split("\t",$_);
		    die "data format error: expecting 7 columns $!" if (scalar(@cols) != 7);

		    my $pmidDotUniq = $cols[0];
		    my $cuisOrIds = $cols[4];

		    my $docType = $cols[1];
		    my $docId = $cols[2];
		    my $sentNo = $cols[3];
		    my $pos = $cols[5];
		    my $length = $cols[6];
		    my $docKey = "$docType,$docId,$sentNo,$pos,$length";
		    
		    if (defined($lastPmid) && ($lastPmid ne $pmidDotUniq)) {
			processOneDoc($lastPmid, $outFH, $dataOneDoc, $method, $minConceptFreq, $minPosteriorProb);
			$dataOneDoc = {};
#	} else {
		    }
		    $dataOneDoc->{$docKey} =  $cuisOrIds;
		    $lastPmid = $pmidDotUniq;
		    
		}    
		processOneDoc($lastPmid, $outFH, $dataOneDoc, $method, $minConceptFreq, $minPosteriorProb)  if (defined($lastPmid));

		close($outFH);
	    }

	    my $logFH;
	    if (defined($multiParameterValues))  {
		open($logFH, ">", "$thisOutputDir.out") or die "Error opening > $thisOutputDir.out";
		select($logFH);
	    } else {
		select(STDERR);
	    }

	    print "\nTotal: $totalCases\nAmbiguous: $totalAmbig (".sprintf("%.2f",$totalAmbig/$totalCases*100)." %)\nAmbiguous fixed: $ambigFixed  (".sprintf("%.2f",$ambigFixed/$totalAmbig*100)." %)\n";
	    print "\nTotal unique ambiguity cases: $uniqueTotalCases\n";
	    print "  Success: $uniqueSuccess (".sprintf("%.2f",$uniqueSuccess/$uniqueTotalCases*100)." %)\n";
	    print "  Failed - Unknown target: $uniqueUnknownTarget (".sprintf("%.2f",$uniqueUnknownTarget/$uniqueTotalCases*100)." %)\n";
	    print "  Failed - Method Not Applicable: $uniqueMethodNA (".sprintf("%.2f",$uniqueMethodNA/$uniqueTotalCases*100)." %)\n";
	    print "  Failed - Rejected due to threshold: $uniqueThrehsholdReject (".sprintf("%.2f",$uniqueThrehsholdReject/$uniqueTotalCases*100)." %)\n\n";

	    select(STDOUT);

	}
    }
}


