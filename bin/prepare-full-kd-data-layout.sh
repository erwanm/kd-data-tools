#!/bin/bash

DIR="$( cd "$( dirname "$0" )" && pwd )"


function generateSymlinks {
    local targetdir="$1"
    local fromTargetToSource="$2" # either ../deduplicated or ../../deduplicated/abstracts or ...
    local sourcedir=$(echo "$targetdir" | sed 's/deduplicated.disambiguated/deduplicated/')
    
    pushd "$targetdir" >/dev/null
    for f in "$fromTargetToSource"/*.raw; do
	ln -s "$f"
    done
    for f in "$fromTargetToSource"/*.tok; do
	ln -s "$f"
    done
    popd >/dev/null
    
}


if [ $# -ne 1 ]; then
    echo "usage: <KD data dir with deduplicated data>" 1>&2
    echo 1>&2
    echo "  Checks that the dir follows the expected layout and creates the" 1>&2
    echo "  structure for disambiguated data." 1>&2
    echo 1>&2
    exit 1
fi

dir="$1"

d="$dir"
if [ ! -d "$d" ]; then
    echo "Error: dir '$d' doesnt exist" 1>&2
    exit 1
fi

d="$dir/unfiltered-medline"
if [ ! -d "$d" ]; then
    echo "Error: dir '$d' doesnt exist" 1>&2
    exit 1
fi

d="$dir/unfiltered-medline/deduplicated"
if [ ! -d "$d" ]; then
    echo "Error: dir '$d' doesnt exist" 1>&2
    exit 1
fi

d="$dir/abstracts+articles"
if [ ! -d "$d" ]; then
    echo "Error: dir '$d' doesnt exist" 1>&2
    exit 1
fi

d="$dir/abstracts+articles/deduplicated"
if [ ! -d "$d" ]; then
    echo "Error: dir '$d' doesnt exist" 1>&2
    exit 1
fi

d="$dir/abstracts+articles/deduplicated/abstracts"
if [ ! -d "$d" ]; then
    echo "Error: dir '$d' doesnt exist" 1>&2
    exit 1
fi

d="$dir/abstracts+articles/deduplicated/articles"
if [ ! -d "$d" ]; then
    echo "Error: dir '$d' doesnt exist" 1>&2
    exit 1
fi

d="$dir/unfiltered-medline/deduplicated.disambiguated"
if [ -d "$d" ]; then
    echo "Error: dir '$d' already exists" 1>&2
    exit 1
fi
mkdir "$d"
generateSymlinks "$d" "../deduplicated"

d="$dir/abstracts+articles/deduplicated.disambiguated"
if [ -d "$d" ]; then
    echo "Error: dir '$d' already exists" 1>&2
    exit 1
fi
mkdir "$d"

d="$dir/abstracts+articles/deduplicated.disambiguated/abstracts"
if [ -d "$d" ]; then
    echo "Error: dir '$d' already exists" 1>&2
    exit 1
fi
mkdir "$d"
generateSymlinks "$d" "../../deduplicated/abstracts"

d="$dir/abstracts+articles/deduplicated.disambiguated/articles"
if [ -d "$d" ]; then
    echo "Error: dir '$d' already exists" 1>&2
    exit 1
fi
mkdir "$d"
generateSymlinks "$d" "../../deduplicated/articles"

