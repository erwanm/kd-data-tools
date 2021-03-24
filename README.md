# Overview

This repository contains some miscellaneous tools for manipulating the "KD data", which is obtained as [the output of my fork](https://github.com/erwanm/knowledgediscovery) of [Jake Lever's knowledgediscovery (KD)](https://github.com/jakelever/knowledgediscovery) system. This KD data contains the full content of Medline and PMC as parsed by the aforementioned system and stored using the ["Tabular Doc-Concept" (TDC) format](https://github.com/erwanm/knowledgediscovery#format-of-the-output-files). The most important tool in this repository is an **ad-hoc concept disambiguation system for the KD data** (usage described in the last section below).  

**CAUTION!** The disambiguation system is a prototype which:

* is **extremely demanding in computational resources**, with the main part requiring around 250G RAM for each process. 
  * With the 2021 KD data, the full process took around 2 months of computations using 3 parallel processes running on high-memory nodes of a cluster.
* has never been properly tested or compared against state of the art disambiguation methods.
* was not the main goal of my research (so far at least), it just happens that the numerous ambiguous cases (around 30%) were an issue for the target downstream application.

Despite all these issues, to the best of my (limited) knowledge there is no other widely available disambiguation system which can be applied straightforwardly to the full UMLS-annotated Medline/PMC data. 


# Requirements

## Software

The code is written in Perl and C++. It requires the Perl module `GetOpt::Std` (possibly also `Carp` but I think it's standard), and a recent enough C++ compiler (you're probably fine).

### Compilation

In the `bin` directory: 

```
g++ -std=c++11 -Wfatal-errors -o disambiguation-for-KD-output disambiguation-for-KD-output.cpp
```


## Data

The input data is made of the output described [here](https://github.com/erwanm/knowledgediscovery).

For the sake of simplicity the commands below assume that the input files/directories are present in the current directory. The path can be adjusted to your setup everywhere, of course.

# I. Deduplication

This step removes a few Medline abstracts for which there are several versions in the data. There are very few such cases it's recommended to remove the duplicates, if only to avoid multiple occurrences of the same PMID.

## Step 1: collect pmids with version which is not the latest

```
bin/extract-non-latest-pmid-versions.pl mesh-descriptors-by-pmid.tsv non-latest-pmid-versions.tsv
```

This should result in a file containing around 2k duplicates:

```
> wc -l non-latest-pmid-versions.tsv 
2128 non-latest-pmid-versions.tsv
```

## Step 2: remove duplicate abstracts 

If needed mount the mined KD data:

```
mkdir /tmp/mined
squashfuse ../knowledgediscovery/mined.sqsh /tmp/mined
```

### unfiltered-medline

```
ls /tmp/mined/mined.unfiltered-medline/abstracts/* | grep -v '.out$' | bin/discard-non-latest-pmid-versions.pl non-latest-pmid-versions.tsv unfiltered-medline.deduplicated
```

Estimated duration: 1h.

### abstracts+articles

Note: this process applies only to the Medline abstracts part of the data.

```
ls /tmp/mined/mined.abstracts+articles/abstracts/* | grep -v '.out$' | bin/discard-non-latest-pmid-versions.pl non-latest-pmid-versions.tsv abstracts+articles.deduplicated
```
Estimated duration: 1h.


### mesh-descriptors-by-pmid

```
echo mesh-descriptors-by-pmid.tsv | ../kd-data-tools/bin/discard-non-latest-pmid-versions.pl -c 3 non-latest-pmid-versions.tsv output
mv output/mesh-descriptors-by-pmid.tsv mesh-descriptors-by-pmid.deduplicated.tsv
```

# II. Generating resources for the disambiguation process

## Converted Mesh descriptors

```
bin/convert-mesh-to-cui.pl -k -l ',' -M  -m cuis  UMLS-2020AB/META/ mesh-descriptors-by-pmid.deduplicated.tsv 5 | cut -f 1-4,6 > mesh-descriptors-by-pmid.deduplicated.cuis.tsv
```
Estimated duration: 20 mn.


```
bin/convert-mesh-to-cui.pl -k -l ',' -M  -m mesh  UMLS-2020AB/META/ mesh-descriptors-by-pmid.deduplicated.tsv 5 | cut -f 1-4,6 > mesh-descriptors-by-pmid.deduplicated.mesh.tsv
```
Estimated duration: 20 mn.


## Non-ambiguous "pairs data"

### Non-ambiguous "pairs data" with converted Mesh descriptors


The resulting dataset represents the 'pairs data' based on only the non-ambiguous concepts, with the addition of converted Mesh descriptors.

**Important: the next step requires at least 32 G memory** (run with more if you can).


```
build-doc-concept-matrix.pl -r ../knowledgediscovery/umlsWordlist.WithIDs.txt -o -d 1 -m -e mesh-descriptors-by-pmid.deduplicated.mesh.tsv:1:5:, -u /tmp/mined/mined.abstracts+articles/ doc-cui-matrix.abstracts+articles.by-paper.unambiguous.with-converted-mesh.mesh.tsv
```

Estimated duration: 3.5 hours.



**Important: the next step requires  250 G memory.**

Note: the `-n` option is used to avoid the unnecessary sorting step. The process requires 18 hours with this option but 24 hours without.


```
calculate-concept-pairs-stats.pl -n doc-cui-matrix.abstracts+articles.by-paper.unambiguous.with-converted-mesh.mesh.tsv 3 pair-stats.abstracts+articles.by-paper.unambiguous.with-converted-mesh.mesh.tsv
```


# III. Disambiguation


## Preparation


### Directory structure

The process expects the whole deduplicated data to be present in a directory `mined` containing the following structure:

- unfiltered-medline
  - deduplicated
- abstracts+articles
  - deduplicated
    - abstracts
    - articles

Notes:

- `unfiltered-medline/deduplicated` and `abstracts+articles/deduplicated/abstracts` are obtained from the deduplication step above
  - These directories do not contain `.out` files
- `abstracts+articles/deduplicated/articles` is obtained directly from the KD mining process


The `abstracts+articles/deduplicated/articles` directory may contain huge `.out` files which can be removed: 

```
rm -f abstracts+articles/deduplicated/articles/*.out
```

Based on the 2021 data, deleting these files saves more than 200 GB. The whole `mined` directory occupies close to 380 GB. At the end of the process it will use around 450 GB.

The following script checks that the directory layout is valid, creates output directories for the disambiguated data and creates the symlinks to `.raw` and `.tok` files in the output directories:

```
prepare-full-kd-data-layout.sh mined/
```

### Splitting data for parallel processing


- The disambiguation process requires 250G memory (for every process of course!)
- The disambiguation process requires reading the "pairs data" which takes a long time (4 to 6 hours). This is done only once for all the input files, so there's a trade off:
  - if many input files are processed sequentially, the whole process is very long
  - if the processes are run in parallel but for few files every time, then a lot of computation time is wasted on loading the pairs data every time.
- Note: the first couple hundreds of abstracts files are very light, they take less time to process than regular files.

The script `run-cascaded-disambiguation.sh` (see below) takes as input a list of input `.cuis` files to process. The input files can be grouped into batches, for examples like this:


```
ls mined/unfiltered-medline/deduplicated/*cuis | split -l 320 -d - um
ls mined/abstracts+articles/deduplicated/abstracts/*cuis | split -l 300 -d - aa.abs
ls mined/abstracts+articles/deduplicated/articles/*cuis | split -l 451 -d - aa.art
```

## Main process

''Caution: requires 250 G memory and a lot of computation time (around 2 months using 3 parallel processes)''

Requires access the data resources computed in step II (see above):

```
mkdir /tmp/data
squashfuse data-for-disamb-etc.sqsh /tmp/data
```

### Run a process for `unfiltered-medline`

```
f=um00; ../kd-data-tools/bin/run-cascaded-disambiguation.sh $f mined/unfiltered-medline/deduplicated.disambiguated/ $f.tmp umlsWordlist.WithIDs.txt /tmp/data/pair-stats.abstracts+articles.by-paper.unambiguous.with-converted-mesh.mesh.tsv 28116370 /tmp/data/mesh-descriptors-by-pmid.deduplicated.mesh.tsv
```

Then same for all the subtasks: `um01`, `um02`,`um03`.

### Run a process for `abstracts+articles/abstracts`

```
f=aa.abs00; ../kd-data-tools/bin/run-cascaded-disambiguation.sh $f mined/abstracts+articles/deduplicated.disambiguated/abstracts/ $f.tmp umlsWordlist.WithIDs.txt /tmp/data/pair-stats.abstracts+articles.by-paper.unambiguous.with-converted-mesh.mesh.tsv 28116370 /tmp/data/mesh-descriptors-by-pmid.deduplicated.mesh.tsv
```

### Run a process for `abstracts+articles/articles`

```
f=aa.art00; ../kd-data-tools/bin/run-cascaded-disambiguation.sh $f mined/abstracts+articles/deduplicated.disambiguated/articles/ $f.tmp umlsWordlist.WithIDs.txt /tmp/data/pair-stats.abstracts+articles.by-paper.unambiguous.with-converted-mesh.mesh.tsv 28116370 /tmp/data/mesh-descriptors-by-pmid.deduplicated.mesh.tsv
```

