#!/bin/bash

script_path=$0
cluster=$1
operation=${2:-plan}
dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
vars_file=${dir}/cluster/${cluster}.tfvars
tfstate_dir=${dir}/.clusterstate/${cluster}
package_dependencies="terraform vault"

usage()
{
  printf "Usage: ${script_path} cluster-name <operation> \n"
  printf "\nCheck available options:\n"
  find ${dir}/cluster -type f -name '*tfvars'| sort | sed 's@'${dir}'\/cluster\/@'${script_path}' @g' | sed 's/.tfvars//g'
  exit 1
}

checkLocal()
{
  val=0
  for package in $package_dependencies
  do
    which ${package} >/dev/null 2>&1
    if [ $? -ne 0 ];then
      printf "You will need package $package installed to execute this script.\n"
      val=1
    fi
  done

  [[ $val -eq 1 ]] && exit 1
}

load_vars ()
{
  [[ ! -s ${vars_file} ]] && usage
  var_list=$(cat ${dir}/cluster/template | grep -v ^"#" | grep = | awk -F "=" {'print $1'} | sort -u)
  for var in ${var_list}
  do
    cat ${vars_file} | grep -q ^"${var}=" 
    [[ $? -ne 0  ]] && echo "$var variable missing on file ${vars_file}" && exit 1
  done
  source ${vars_file}
}

tf_init()
{
  [[ ! -d ${tfstate_dir} ]] && mkdir -p ${tfstate_dir}
  rm ${tfstate_dir}/*.tf 2>/dev/null
  cp ${dir}/conf/*.tf ${tfstate_dir}
  cp ${dir}/conf/${cluster_name}/* ${tfstate_dir} 2>/dev/null
  cd ${tfstate_dir}

  vault read -field=value secret/${secret_location}/gke_terraform/key > gckey.json
  [[ ! -s gckey.json ]] && echo "Unable to retrieve secret from secret/${secret_location}/gke_terraform/key location" && exit 1 
 
  echo "Execution terraform init on bucket terraform-${cluster_name}"
  terraform init \
   -backend-config="bucket=terraform-${cluster_name}" \
   -backend-config="credentials=gckey.json" | grep -v rerun | grep -i "Initializ" 
 
  [[ $? -ne 0 ]] && exit 1
}

tf_apply()
{
  gke_service_account="secret/${secret_location}/gke_terraform/key"

  terraform ${operation} \
    -var-file=${vars_file} \
    -var uuid=$(openssl rand -hex 32) \
    -var gke_service_account=${gke_service_account}
}

checkLocal
[[ -z ${cluster} ]] && usage

load_vars
tf_init
tf_apply
