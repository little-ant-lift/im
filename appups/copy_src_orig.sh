#!/bin/bash
App=$1
replacetxt=`head -n 1 ${App}.appup.src`
if [ "${App}" == "msync" ]
then
    sed 's/'${replacetxt}'\(.*\)/\{{cmd, \"env bash ..\/get_git_ver_string.sh\"\},\1/g' ${App}.appup.src > ${App}.appup.src.orig
elif [ "${App}" != "lager" ]&&[ "${App}" != "brod" ] && [ "${App}" != "supervisor3" ] &&[ "${App}" != "kafka_protocol" ] && [ "${App}" != "snappyer" ]
then
    sed 's/'${replacetxt}'\(.*\)/\{git,\1/g' ${App}.appup.src > ${App}.appup.src.orig
else
    cp ${App}.appup.src  ${App}.appup.src.orig
fi
echo "." >> ${App}.appup.src.orig
