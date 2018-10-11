#!/bin/bash
vsn=`bash get_git_ver_string.sh`
cp rel/msync/releases/${vsn}/msync.boot rel/msync/releases/${vsn}/start.boot
# change RELEASE to relative pat
pwd=$(pwd)
respath=$(echo ${pwd}"/rel/msync" |sed -e 's/\//\\\//g' )
replacepath="."
sed 's/'${respath}'\(.*\)/'${replacepath}'\1"/g' rel/msync/releases/RELEASES > rel/msync/releases/RELEASES.tmp
mv rel/msync/releases/RELEASES.tmp rel/msync/releases/RELEASES
