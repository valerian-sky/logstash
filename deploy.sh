#!/bin/bash
echo "usage \$1 = username, \$2 =public ip , \$3 = image repository, \$4 = image tag, \$5 = targetEnv, [\$6 azureswarm repo and project brach]"
echo e.g "dm develop opuscapita/customer dev gr4per/azureswarm/master"
username=$1
public_ip=$2
img_hub_repo=$3
img_tag=$4
targetEnv=$5
repoPath=$6
serviceName=$CIRCLE_PROJECT_REPONAME

if [ -z $6 ]; then echo "too few params" && exit 1; fi

# transform task_template.json by injecting env vars
if [[ -f task_template.json ]]
then
  echo "task_template found, mapping..."
else
  echo "task_template not found, exiting..."
  exit 1
fi
envVars=$(cat task_template.json | grep -P -o "[$]\{.*?\}" | sed -e "s/[$][{]//g" |sed -e "s/[}]//g")
cp task_template.json task_template_mapped.json
for ev in $envVars
do
  evk=$(echo $ev | sed -e "s/[:]env/$targetEnv/g")
  #if [ -z ${ev+x} ]; 
  if [ -v `echo $evk` ];
  then 
    echo "$evk is set, injecting"; 
    sed -i "s/[$][{]$ev[}]/$(eval echo '$'$evk)/g" task_template_mapped.json
  else 
    echo "$evk is required by task_template.json but unset."; exit 1; 
  fi
done

wanted_params=$(jq '.production+.default|keys|@sh' task_template_mapped.json | sed -e "s/\"//g" | sed -e "s/'//g")
curl https://raw.githubusercontent.com/$repoPath/field_defs.json > field_defs.json
unset docker_cmd
echo "targetEnv=$targetEnv"

#inject consul keys
keyInjectConfig=$(jq -e "if (.$targetEnv|has(\"oc-consul-injection\")) then .$targetEnv|.[\"oc-consul-injection\"] else .default|.[\"oc-consul-injection\"] end" task_template_mapped.json)
if [[ "$?" > 0 ]]; then
  echo "skipping consul key injection as oc-consul-injection is not set in task_template.json"
else
  echo "going to do consul key injection"
  curlScript=""
  lv=$(echo $keyInjectConfig | jq --raw-output "keys|\"\\\"\"+join(\"\\\" \\\"\")+\"\\\"\"")
  for lvx in $lv ;do 
    value=$(echo $keyInjectConfig |jq ".[$lvx]")
    nlvx=$(echo $lvx | sed -e "s/[\"]//g")
    curlScript="${curlScript}curl -X PUT -d ${value} http://localhost:8500/v1/kv/${serviceName}/${nlvx}; "
  done
  echo "curlScript=$curlScript"
  echo $curlScript | ssh $username@$public_ip -p 2200 -o "StrictHostKeyChecking no" -o LogLevel=error -o "StrictHostKeyChecking no"
fi

curl https://raw.githubusercontent.com/$repoPath/build_docker_command.sh > build_docker_command.sh
#chmod +x build_docker_command.sh
source build_docker_command.sh

# get current service details
# if service exists exit code should be 0, else 1 ($? is 0|1)
if ! echo "docker service inspect $CIRCLE_PROJECT_REPONAME" | ssh $username@$public_ip -p 2200 -o "StrictHostKeyChecking no" -o LogLevel=error > service_config.json
then
  echo "service not found"
  jq -e "" task_template_mapped.json > /dev/null
  if [[ "$?" > 0 ]]
  then 
    echo "no task_template_mapped.json found, create mode unsupported"
  else 
    #create the service secret
    secretName="$serviceName-consul-key"
    echo "secretName='$secretName'"
    serviceSecret=$(openssl rand -base64 32)
    secretId=$(ssh $username@$public_ip -p 2200 -o "StrictHostKeyChecking no" << HERE
docker secret create "$secretName" - <<< "$serviceSecret" 
HERE
)   
    if [[ "$?" > 0 ]] ; then
      echo "error creating the service secret"
      exit 1;
    fi
    echo $secretId | tail -1 | grep -o -P "[a-z0-9]+$"
    echo "secretId=$secretId"
    
    dbinit=$(jq -e "if (.$targetEnv|has(\"oc-db-init\")) then .$targetEnv|.[\"oc-db-init\"] else .default|.[\"oc-db-init\"] end" task_template_mapped.json)
    if [[ "$?" > 0 ]]; then
      echo "skipping db handling as oc-db-init is not set in task_template.json"
    else
      echo "going to create db and user if not exists"
      populate=$(echo $dbinit | jq -e --raw-output ".[\"populate-test-data\"]")
      if [[ "$?" > 0 ]]; then echo "populate-test-data not found in task-template.json/oc-db-init, setting to false" && populate=false; fi
      curl https://raw.githubusercontent.com/$repoPath/deploy_db.sh > deploy_db_cp.sh
      chmod +x deploy_db_cp.sh
      ./deploy_db.sh $target_user $public_ip $serviceName $populate <<< \"$MYSQL_PWD\"
    fi
    
    build_docker_create "$secretName"
  fi
  docker_cmd="$docker_cmd $img_hub_repo:$img_tag"
else 
  echo "service exists!"
  # now strip the ssh banner and remove original output
  tail -n +`grep -m1 -n "^\[\s*" service_config.json | grep -o "[0-9]*"` service_config.json > service_config_clean.json
  rm service_config.json
  
  jq -e "" task_template_mapped.json > /dev/null
  if [[ "$?" > 0 ]]
  then 
    echo "no task_template_mapped.json found, using simple update mode (only updating to new image)"
    docker_cmd="docker service update --force --image"
  else 
    build_docker_update
  fi
  docker_cmd="$docker_cmd $img_hub_repo:$img_tag $CIRCLE_PROJECT_REPONAME"
fi
#username=$1
#public_ip=$2
#img_hub_repo=$3
#img_tag=$4

echo "docker command is $docker_cmd"
#exit 1
serviceId=$(jq --raw-output ".[0]|.ID" service_config_clean.json)

DS2='SERVICE_ID=$('
DS2="$DS2$docker_cmd)"
DS2+='
echo "triggered update of service with id $SERVICE_ID"
monitor() {
for attempt in {1..30}; do
  srvStatus=$(docker inspect $SERVICE_ID | jq --raw-output --exit-status .[0].UpdateStatus.State)
  if [ $srvStatus = "updating" ]; then
            echo "Waiting for deployment to complete: $srvStatus"
            sleep 5
        else
          if [ $srvStatus = "completed" ]; then
            echo "Deployment done: $srvStatus"
            return 0
          else
            echo "Deployment failed: status = $srvStatus"
            return 1
          fi
        fi
done
  echo "Service update took too long."
  return 1
}
monitor
'
echo "$DS2" | ssh $username@$public_ip -p 2200 -o "StrictHostKeyChecking no"
#echo "$DS2" > run_in_ssh.txt
