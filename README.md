# Overview

This repository contains some miscellaneous tools for manipulating the "KD data", which is obtained as [the output of my fork](https://github.com/erwanm/knowledgediscovery) of [Jake Lever's knowledgediscovery (KD)](https://github.com/jakelever/knowledgediscovery) system. This KD data contains the full content of Medline and PMC as parsed by the aforementioned system and stored using the ["Tabular Doc-Concept" (TDC) format](https://github.com/erwanm/knowledgediscovery#format-of-the-output-files). The most important tool in this repository is an **ad-hoc concept disambiguation system for the KD data** (described in the last section below).  

CAUTION: the disambiguation system is a prototype which:

* is **extremely demanding in computational resources**, with the main part requiring around 250G RAM for each process. 
  * With the 2021 KD data, the full process took around 2 months of computations using 3 parallel processes running on high-memory nodes of a cluster.
* has never been properly tested or compared against state of the art disambiguation methods.
* was not the main goal of my research (so far at least), it just happens that the numerous ambiguous cases (around 30%) were an issue for the target downstream application.

Despite all these issues, to the best of my (limited) knowledge there is no other widely available disambiguation system which can be applied straightforwardly to the full UMLS-annotated Medline/PMC data. 


# Requirements

## Software

The code is written in Perl and C++. It requires the Perl module `GetOpt::Std` (possibly also `Carp` but I think it's standard), and a recent enough C++ compiler (you're probably fine).

## Data

The input data is made of the output described [here](https://github.com/erwanm/knowledgediscovery).

For the sake of simplicity the commands below assume that the input files/directories are present in the current directory. The path can be adjusted to your setup everywhere, of course.

# Deduplication

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

### abstracts+articles

Note: this process applies only to the Medline abstracts part of the data.

```
ls /tmp/mined/mined.abstracts+articles/abstracts/* | grep -v '.out$' | bin/discard-non-latest-pmid-versions.pl non-latest-pmid-versions.tsv abstracts+articles.deduplicated
```

### mesh-descriptors-by-pmid

```
echo mesh-descriptors-by-pmid.tsv | ../kd-data-tools/bin/discard-non-latest-pmid-versions.pl -c 3 non-latest-pmid-versions.tsv output
mv output/mesh-descriptors-by-pmid.tsv mesh-descriptors-by-pmid.deduplicated.tsv
```

