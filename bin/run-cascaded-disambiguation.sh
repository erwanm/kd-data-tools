#!/bin/bash

DIR="$( cd "$( dirname "$0" )" && pwd )"




if [ $# -ne 7 ]; then
    echo "usage: $0 <input cuis files> <specific output dir> <intermediate data dir> <umls words file> <unambiguous pairs file> <nb docs> <mesh by pmid file>" 1>&2
    echo 1>&2
    echo "  Runs the full cascading disambiguation process for a list of cuis files given" 1>&2
    echo "  on STDIN." 1>&2
    echo "  <specific output dir> is the dir where the resulting cuis files will be"  1>&2
    echo "  written. For safety reasons it must already exist." 1>&2
    echo "  <intermediate data dir> is the dir where intermediate steps and '.stats'" 1>&2
    echo "  files will be written (for information purposes)." 1>&2
    echo "  requires the number of documents  <nb docs> used to build the <unambiguous pairs file> = " 1>&2
    echo "  pair-stats.abstracts+articles.by-paper.unambiguous.with-converted-mesh.mesh.tsv" 1>&2
    echo "  <mesh by pmid file> = mesh-descriptors-by-pmid.deduplicated.mesh.tsv" 1>&2
    echo 1>&2
    exit 1
fi

inputFiles="$1"
targetdir="$2"
workdir="$3"
umlsWordsFile="$4"
pairsFile="$5"
nbDocs="$6"
meshbypmidFile="$7"


d="$targetdir"
if [ ! -d "$d" ]; then
    echo "Error: dir '$d' doesnt exist" 1>&2
    exit 1
fi

if [ ! -f "$umlsWordsFile" ]; then
    echo "Error: file '$umlsWordsFile' doesnt exist" 1>&2
    exit 1
fi

if [ ! -f "$pairsFile" ]; then
    echo "Error: file '$pairsFile' doesnt exist" 1>&2
    exit 1
fi

if [ ! -f "$meshbypmidFile" ]; then
    echo "Error: file '$meshbypmidFile' doesnt exist" 1>&2
    exit 1
fi

d="$workdir"
[ -d "$d" ] || mkdir "$d"

# read input cuis files and store 
cat "$inputFiles" > "$workdir"/input.files

basicDir="$workdir/1.basic"
[ -d "$basicDir" ] || mkdir "$basicDir"
echo "*** STEP $basicDir"
cat "$workdir"/input.files | $DIR/disambiguation-for-KD-output -r umlsWordlist.WithIDs.txt -b 0.95 -a basic "$nbDocs" "$pairsFile" "$basicDir"
if [ $? -ne 0 ]; then
    echo "Error step $basicDir" 1>&2
    exit 1
fi
echo

advDir="$workdir/2.advanced"
[ -d "$advDir" ] || mkdir "$advDir"
echo "*** STEP $advDir"
ls "$basicDir"/*.cuis | disambiguation-for-KD-output -b 0.95 -f 1 -a advanced -d -e "$meshbypmidFile:1:5:,"  "$nbDocs" "$pairsFile" "$advDir"
if [ $? -ne 0 ]; then
    echo "Error step $advDir" 1>&2
    exit 1
fi
echo

nbDir="$workdir/3.NB"
[ -d "$nbDir" ] || mkdir "$nbDir"
echo "*** STEP $nbDir"
ls "$advDir"/*.cuis | disambiguation-for-KD-output -b 0.95 -f 1 -a NB -d -e "$meshbypmidFile:1:5:,"  "$nbDocs" "$pairsFile" "$nbDir"
if [ $? -ne 0 ]; then
    echo "Error step $nbDir" 1>&2
    exit 1
fi

mv "$targetdir"/*.cuis "$targetdir"
