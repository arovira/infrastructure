#!/usr/bin/env bash
local_script=$0
script_name=$( basename ${local_script} )
script_folder="$( dirname "${BASH_SOURCE[0]}" )"
logfile=/tmp/$(printf "%s\n" "${script_name}" | sed 's/.sh$/.log/g')
package_dependencies="gcloud kubectl helm vault"

loadFunctions()
{
  source .include/functions.sh
}

# Start script logic

cd ${script_folder}
loadFunctions
checkLocal
env=$1
cluster=$2
checklist_file=.conf/$env/checklist/$cluster

[[ -z "${2}" ]] && usage
loadEnv ${env}

printf "\n#########\n" >> ${logfile}
myLog "Starting bootstrap script with following values: \n${arguments}"

myLog "Connecting to cluster ${cluster_name}"
connectCluster ${cluster_name} ${project} ${location}

[[  ! -f ${checklist_file} ]] && myLog "${checklist_file} file not found." 1
echo
myLog "Here are the actions that will be performed:"
cat ${checklist_file} | sed '/^$/d' | grep -v ^"#"
printf "\nPress enter to continue" ; read answer

cat ${checklist_file} | sed '/^$/d' | grep -v ^"#" | while read action else
do
  echo
  type $action >/dev/null 2>&1
  [[ $? -ne 0 ]] && myLog "${checklist_file} file has unknown action $action. Please check" 1
  myLog "Starting action $action ${else}"
  ${action} ${else}
done
