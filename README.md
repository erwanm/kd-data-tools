# kd-data-tools

This repository contains some miscellaneous tools for manipulating the "KD data", which is obtained as [the output of my fork](https://github.com/erwanm/knowledgediscovery) of [Jake Lever's knowledgediscovery (KD)](https://github.com/jakelever/knowledgediscovery) system. This KD data contains the full content of Medline and PMC as parsed by the aforementioned system and stored using the ["Tabular Doc-Concept" (TDC) format](https://github.com/erwanm/knowledgediscovery#format-of-the-output-files). The most important tool in this repository is an **ad-hoc concept disambiguation system for the KD data** (described in the last section below).  

CAUTION: the disambiguation system is prototype which:

* is **extremely demanding in computational resources**, with the main part requiring around 250G RAM for each process. 
  * With the 2021 KD data, the full process took around 2 months of computations using 3 parallel processes running on high-memory nodes of a cluster.
* has never been properly tested or compared against state of the art disambiguation methods.
* was never the main goal of the research (so far at least), it just happens that the numerous ambiguous cases (around 30%) were an issue for the target downstream application.

Yet to the best of my limited knowledge there is no other widely available disambiguation system which can be applied straightforwardly to the full UMLS-annotated Medline/PMC data. So this a terrible system but that's the only one I know of.
