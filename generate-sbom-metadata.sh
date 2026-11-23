#!/bin/sh
#
# Records the upstream sources (with full git commit hashes) used to build
# llvm-mingw, in a form suitable for generating CycloneDX SBOMs.
#
# usage: generate-sbom-metadata.sh <component> <srcdir> [outdir]
#
# <component> is one of: llvm, mingw-w64
#
# Output (in <outdir>, default $PREFIX/sbom):
#   upstream-purls.txt         - purls of upstream sources, pinned to full hashes
#   upstream-components.json   - merged CycloneDX component fragments (JSON array)
#   components.d/*.json        - the individual per-component fragments

set -e

COMPONENT=$1
SRCDIR=$2

case $COMPONENT in
llvm)
    GH_REPO=llvm/llvm-project
    NAME="LLVM"
    BOM_REF="org.llvm.llvm-project"
    LICENSE_EXPRESSION="Apache-2.0 WITH LLVM-exception"
    ;;
mingw-w64)
    GH_REPO=mingw-w64/mingw-w64
    NAME="mingw-w64"
    BOM_REF="org.mingw.w64"
    LICENSE_ID="ZPL-2.1"
    ;;
*)
    echo "$0: Unknown component $COMPONENT" >&2
    exit 1
    ;;
esac

DIST_URL=${SBOM_DISTRIBUTION_URL:-https://github.com/mstorsjo/llvm-mingw}
OUTDIR=${3:-${SBOM_OUT:-${PREFIX:+$PREFIX/sbom}}}
OUTDIR=${OUTDIR:-$PWD/sbom-output}

HASH=$(cd "$SRCDIR" && git rev-parse HEAD 2>/dev/null) || {
    echo "$0: Warning: can't determine git revision of $SRCDIR, skipping $COMPONENT" >&2
    exit 0
}
TAG=$(cd "$SRCDIR" && git describe --tags --exact-match 2>/dev/null || true)

case $TAG in
llvmorg-*) DISPLAY=${TAG#llvmorg-} ;;
"")        DISPLAY=$HASH ;;
*)         DISPLAY=$TAG ;;
esac

ARCHIVE_REF=${TAG:-$HASH}

mkdir -p "$OUTDIR/components.d"

# 1. Upstream purl list (always pinned to a full commit hash)
PURLFILE=$OUTDIR/upstream-purls.txt
grep -v "^pkg:github/$GH_REPO@" "$PURLFILE" > "$PURLFILE.new" 2>/dev/null || true
printf 'pkg:github/%s@%s\n' "$GH_REPO" "$HASH" >> "$PURLFILE.new"
mv "$PURLFILE.new" "$PURLFILE"

# 2. CycloneDX component fragment
FRAGMENT=$OUTDIR/components.d/$COMPONENT.json
{
    printf '\t\t{\n'
    printf '\t\t\t"type": "library",\n'
    printf '\t\t\t"name": "%s",\n' "$NAME"
    printf '\t\t\t"bom-ref": "%s",\n' "$BOM_REF"
    printf '\t\t\t"version": "%s",\n' "$DISPLAY"
    if [ -n "$LICENSE_EXPRESSION" ]; then
        printf '\t\t\t"licenses": [\n\t\t\t\t{\n\t\t\t\t\t"expression": "%s"\n\t\t\t\t}\n\t\t\t],\n' "$LICENSE_EXPRESSION"
    else
        printf '\t\t\t"licenses": [\n\t\t\t\t{\n\t\t\t\t\t"license": {\n\t\t\t\t\t\t"id": "%s"\n\t\t\t\t\t}\n\t\t\t\t}\n\t\t\t],\n' "$LICENSE_ID"
    fi
    printf '\t\t\t"externalReferences": [\n'
    printf '\t\t\t\t{\n\t\t\t\t\t"type": "website",\n\t\t\t\t\t"url": "%s"\n\t\t\t\t},\n' "$DIST_URL"
    printf '\t\t\t\t{\n\t\t\t\t\t"type": "vcs",\n\t\t\t\t\t"url": "https://github.com/%s"\n\t\t\t\t},\n' "$GH_REPO"
    printf '\t\t\t\t{\n\t\t\t\t\t"type": "distribution",\n\t\t\t\t\t"url": "%s"\n\t\t\t\t},\n' "$DIST_URL"
    printf '\t\t\t\t{\n\t\t\t\t\t"type": "source-distribution",\n\t\t\t\t\t"url": "https://github.com/%s/archive/%s.zip"\n\t\t\t\t}\n' "$GH_REPO" "$ARCHIVE_REF"
    printf '\t\t\t],\n'
    printf '\t\t\t"purl": "pkg:github/%s@%s",\n' "$GH_REPO" "$HASH"
    printf '\t\t\t"properties": [\n'
    printf '\t\t\t\t{\n\t\t\t\t\t"name": "upp:deployment-mode",\n\t\t\t\t\t"value": "static-third-party"\n\t\t\t\t}' 
    if [ -n "$TAG" ]; then
        printf ',\n\t\t\t\t{\n\t\t\t\t\t"name": "llvm-mingw:git-tag",\n\t\t\t\t\t"value": "%s"\n\t\t\t\t}' "$TAG"
    fi
    printf '\n'
    printf '\t\t\t]\n'
    printf '\t\t}\n'
} > "$FRAGMENT"

# 3. Merge all fragments into one JSON array
MERGED=$OUTDIR/upstream-components.json
printf '[\n' > "$MERGED"
first=true
for f in "$OUTDIR"/components.d/*.json; do
    [ -e "$f" ] || break
    if $first; then first=false; else printf ',\n' >> "$MERGED"; fi
    cat "$f" >> "$MERGED"
done
printf ']\n' >> "$MERGED"

echo "$0: Recorded $GH_REPO at $HASH in $OUTDIR"
