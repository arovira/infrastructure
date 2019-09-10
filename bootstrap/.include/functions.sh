usage()
{
  printf "Usage: ${local_script} enviroment cluster <zone>

Available configurations:
$(find .conf -type f 2>/dev/null | grep -v checklist | tr '/' ' ' | sed 's@.conf@'${local_script}'@g')\n"

  if [ ! -d .conf ];then
   printf "\nTo add a configuration file, follow this example:
mkdir -p .conf/staging
echo \"cluster_name=xxx\nproject=xxx\ndomain=xxx\nenvironment=development\" > .conf/development/xxx\n"
  fi
  exit 1
}

myLog()
{
  [[ -z "${logfile}" ]] && logfile=/tmp/default.log
  printf "[$(date +%Y-%m-%d" "%H:%M:%S)] $1\n" | tee -a ${logfile}
  [[ ! -z $2 ]] && exit $2
  return 0
}

loadEnv()
{
  case ${1} in
    Dev*|dev*) env_conf_file=.conf/development/${cluster};;
    Prod*|prod*) env_conf_file=.conf/production/${cluster};;
    Stag*|stag*) env_conf_file=.conf/staging/${cluster};;
    *) usage;;
  esac
  [[ ! -f ${env_conf_file} ]] && myLog "${env_conf_file} config file not found" && usage
  source ${env_conf_file}
  arguments=$(cat ${env_conf_file})
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

  [[ $val -eq 1 ]] && myLog "Exit" 1
}

check_gcloud_value()
{
  config=$1
  value=$2

  gcloud config list ${config} 2>/dev/null | grep -q " = ${value}$"
  if [ $? -ne 0 ];
  then
    if [ -z $value ]; then
      gcloud config list ${config} 2>/dev/null | grep -q "(unset)"
      if [ $? -ne 0 ];then
         myLog "Unsetting gcloud config ${config}"
        gcloud config unset ${config}
      fi
    else
      myLog "Updating gcloud config ${config} to ${value}"
      gcloud config set ${config} ${value}
    fi
  fi
}

get_region_from_location()
{
  location=$1

  test=$( echo "${location}" | awk -F"-" {'print $3'} )
  if [ -z ${test} ];then
    export KUBERNETES_REGION=${location}
    export KUBERNETES_ZONE=""
    export LOCATION="--region ${location}"
  else
    export KUBERNETES_ZONE=${location}
    export KUBERNETES_REGION=$( echo ${location} | awk -F"-" {'print $1"-"$2'} )
    export LOCATION="--zone ${location}"
  fi
}

connectCluster()
{
  local cluster=$1
  local project=$2
  local location=$3

  get_region_from_location ${location}

  [[ -z ${location} ]] && myLog "No location for cluster $cluster indicated" 1

  cat ~/.kube/config | grep -q "current-context: gke_${project}_${location}_${cluster}"
  if [ $? -ne 0 ]; then
    myLog "Connecting to gke cluster ${cluster} on ${project} project and ${location} location"
    gcloud container clusters get-credentials ${cluster} --project ${project} ${LOCATION}
  fi

  check_gcloud_value compute/zone ${KUBERNETES_ZONE}
  check_gcloud_value compute/region ${KUBERNETES_REGION}
  check_gcloud_value project ${project}
  check_gcloud_value container/cluster ${cluster}

  # cluster configuration
  export KUBERNETES_PROJECT=${project}
  export KUBERNETES_CLUSTER=${cluster}
  export KUBERNETES_USER=$(gcloud config list account 2>/dev/null | grep account | awk {'print $NF'})
}

check_helm()
{
  helm ls > /dev/null 2>&1
  [[ $? -eq 0 ]] && myLog "Helm already initialized" && return 0

  myLog "Installing Tiller"
  #curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get 2>/dev/null | bash 2>/dev/null
  applyService k8s/helm/tiller.yaml

  myLog "Initializing helm. This process might take some minutes on the first execution"
  helm init --service-account tiller --wait >/dev/null
  kubectl patch deployment tiller-deploy --namespace=kube-system --type=json --patch='[{"op": "add", "path": "/spec/template/spec/containers/0/command", "value": ["/tiller", "--listen=localhost:44134"]}]'

  sleep_count=60
  while [ ${sleep_count} -gt 0 ]
  do
    helm ls > /dev/null 2>&1
    [[ $? -eq 0 ]] && break
    printf "."
  done
  printf "\n"
  helm ls > /dev/null
  [[ $? -ne 0 ]] && myLog "Please seek to solve above error" 1
}

applyService()
{
  file=$1
  options=${*:2}

  [[ ! -f ${file} ]] && myLog "File ${file} not found" && return 1

  myLog "Applying file ${file} with options ${options}"
  kubectl apply -f ${file} ${options} | tee -a ${logfile}

  if [ ${PIPESTATUS[0]} -ne 0 ];then
     kubectl delete -f ${file} ${options}
     myLog "Error applying service ${file}. Terminating script" 1
  fi
}

run_helm()
{
  name=$1
  repo=$2
  options=${*:3}

  myLog "Helm request $name from $repo with following options: $options"

  helm ls --all | grep ^"${name}" 2>/dev/null
  if [ $? -ne 0 ];then
    myLog "Executing: helm install --name $name $repo $options"
    helm install --name $name $repo $options 2> /tmp/errors
    if [ -s /tmp/errors ];then
      cat /tmp/errors | grep customresourcedefinitions
      if [ $? -eq 0 ];then
        [[ -z $customresourcedefinitions ]] && myLog "customresourcedefinitions dependencies missing" 1
        for crd in $customresourcedefinitions
        do
          myLog "Removing $crd customresourcedefinitions"
          kubectl delete customresourcedefinitions $crd
        done
        helm delete --purge $name
        helm install --name $name $repo $options
      else
        cat /tmp/errors
        myLog "Error installing helm package" 1
      fi
    fi
    helm ls --all $name
  else
    myLog "To update deployemnt execute: helm upgrade $options $name $repo"
  fi
}

kong_ingress_private()
{
  customresourcedefinitions=""
  run_helm kong stable/kong \
  --namespace kong \
  -f k8s/kong/values_private.yaml \
  --version 0.14.1
}

kong_ingress_public()
{
  customresourcedefinitions=""
#  kong_pg_user=$(vault read -field=user ${vault_dir}/${env}/helm/kong_pg)
  kong_pg_pwd=$(vault read -field=pwd ${vault_dir}/${env}/helm/kong_pg)
  [[ -z ${kong_pg_pwd} ]] && myLog "Unable to find ${vault_dir}/${env}/helm/kong_pg secret. Please add"

  ip_name=kong-static-${cluster_name}
  IP=$(gcloud compute addresses describe ${ip_name} --region ${KUBERNETES_REGION} --format 'value(address)' 2>/dev/null)
  if [ -z $IP ];then
    myLog "Creating global static IP address ${ip_name} on region ${KUBERNETES_REGION}"
    gcloud compute addresses create ${ip_name} --region ${KUBERNETES_REGION}
    IP=$(gcloud compute addresses describe ${ip_name} --region ${KUBERNETES_REGION} --format 'value(address)')
  fi

  run_helm kong stable/kong \
  --namespace kong \
  -f k8s/kong/values_public.yaml \
  --version 0.14.1 \
  --set proxy.loadBalancerIP=$IP \
  --set postgresql.postgresqlPassword=${kong_pg_pwd}
}

kong_setup()
{
  for setup in $*
  do
    applyService k8s/kong/$setup.yaml
  done
}

get_vault_cloudflare()
{
  vault_folder="secret/global/cloudflare"
  cloudflare_email=$(vault read -field=value ${vault_folder}/email)
  cloudflare_api_key=$(vault read -field=value ${vault_folder}/global_api_key)
  [[ -z ${cloudflare_api_key} ]] && myLog "Error retrieving cloudflare secrets (location ${vault_folder}) Check secret access" 1
}

cloudflare_dns()
{
  customresourcedefinitions=""
  cf_proxied="true"
  if [ "$1" = "private" ]; then
    cf_proxied="false"
  fi

  get_vault_cloudflare
  local namespace=cloudflare

  run_helm cloudflare stable/external-dns \
  -f k8s/cloudflare/external-dns.yaml \
  --namespace ${namespace} \
  --set cloudflare.apiKey=${cloudflare_api_key} \
  --set cloudflare.email=${cloudflare_email}  \
  --set cloudflare.proxied=${cf_proxied} \
  --set domainFilters[0]=${domain} \
  --set txtOwnerId=k8s-deployments-${KUBERNETES_CLUSTER}
# --set logLevel="debug"

  kubectl create clusterrolebinding default-admin --clusterrole cluster-admin --serviceaccount=${namespace}:default 2>/dev/null
}


cert_manager()
{
  customresourcedefinitions="certificates.certmanager.k8s.io clusterissuers.certmanager.k8s.io issuers.certmanager.k8s.io"
  get_vault_cloudflare
  local namespace=certmanager

  run_helm certmanager stable/cert-manager \
  -f k8s/cert-manager/cert-manager.yaml \
  --namespace ${namespace} \
  --version 0.5.2 \
  --set ingressShim.defaultIssuerName=letsencrypt-${env} \
  --set ingressShim.defaultIssuerKind=ClusterIssuer

  cat k8s/cert-manager/clusterIssuer-template.yaml | sed 's/ENVTOREPLACE/'${env}'/g' | sed 's/EMAILTOREPLACE/'${cloudflare_email}'/g' > /tmp/clusterIssuer.yaml
  applyService /tmp/clusterIssuer.yaml

  kubectl get secret cloudflare-api-key -n ${namespace} >/dev/null 2>&1
  [[ $? -ne 0 ]] && kubectl create secret generic cloudflare-api-key --from-literal=api-key=${cloudflare_api_key} -n ${namespace}
}

gcp_bucket()
{
  bck=bck-gcp-resources-${environment}
  myLog "Checking if ${bck} exist or need to be created"
  gcloud compute backend-buckets list 2>/dev/null | grep ${bck}
  if [ $? -ne 0 ]; then
    myLog "Creating backend bucket: gcloud compute backend-buckets create ${bck} --enable-cdn --gcs-bucket-name=gcp-resources-${environment}"
    gcloud compute backend-buckets create ${bck} --enable-cdn --gcs-bucket-name=gcp-resources-${environment}
  fi
}

prometheus_operator()
{
  customresourcedefinitions="alertmanagers.monitoring.coreos.com podmonitors.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com servicemonitors.monitoring.coreos.com"
  namespace=monitoring
  applyService k8s/prometheus-operator/storage_class.yaml
  STORAGE_SIZE="100Gi"
  AIVEN_SERVICE="kafka-staging-dev-8889.aivencloud.com"
#  AIVEN_USERNAME="prom9mb9"
#  AIVEN_PASSWORD="mdfev3vgbw65cmct"
#  AIVEN_HOST="kafka-staging-dev-8889.aivencloud.com"
  if [ "${environment}" = "production" ]; then
    STORAGE_SIZE="200Gi"
    AIVEN_SERVICE="kafka-prod-dev-8889.aivencloud.com"
#    AIVEN_USERNAME="promdcfx"
#    AIVEN_PASSWORD="lxmp0ntvrfz9gos2"
#    AIVEN_HOST="kafka-prod-dev-8889.aivencloud.com"
  fi
  PROMETHEUS_URL="prometheus-${app_shortcode}-${env}.${domain}"
  AIVEN_USERNAME=$(vault read -field=value secret/global/aiven/${env}/service_integrations/username)
  AIVEN_PASSWORD=$(vault read -field=value secret/global/aiven/${env}/service_integrations/password)
  AIVEN_HOST=$(vault read -field=value secret/global/aiven/${env}/service_integrations/host)

  cat k8s/prometheus-operator/values.yaml | \
  sed 's/PROMETHEUS_URL-toreplace/'$PROMETHEUS_URL'/g' | \
  sed 's/STORAGE_SIZE-toreplace/'$STORAGE_SIZE'/g' | \
  sed 's/AIVEN_SERVICE-toreplace/'$AIVEN_SERVICE'/g' | \
  sed 's/AIVEN_USERNAME-toreplace/'$AIVEN_USERNAME'/g' | \
  sed 's/AIVEN_PASSWORD-toreplace/'$AIVEN_PASSWORD'/g' | \
  sed 's/AIVEN_HOST-toreplace/'$AIVEN_HOST'/g' > /tmp/prometheus-operator-values.yaml

  run_helm prometheus stable/prometheus-operator \
  --namespace ${namespace} \
  -f /tmp/prometheus-operator-values.yaml 
}

prometheus()
{
  customresourcedefinitions=""
  namespace=monitoring

  applyService k8s/prometheus/storage_class.yaml

  storage="100Gi"
  [[ "${environment}" = "production" ]] && storage="200Gi"
  run_helm prometheus stable/prometheus \
  --namespace ${namespace} \
  -f k8s/prometheus/values.yaml \
  --set server.persistentVolume.size="${storage}"
  #--version 8.4.1 \

  ENDPOINT="prometheus-${app_shortcode}-${env}.${domain}"
  cat k8s/prometheus/ingress_template.yaml | sed 's/ENVTOREPLACE/'${env}'/g' | sed 's/HOSTTOREPLACE/'$ENDPOINT'/g' > /tmp/prometheus.yaml
  applyService /tmp/prometheus.yaml -n ${namespace}
}

zookeeper()
{
  customresourcedefinitions=""
  run_helm zookeeper incubator/zookeeper \
  --namespace zookeeper \
  -f k8s/zookeeper/values.yaml
}
