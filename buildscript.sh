#!/bin/bash

hub_repo=$1
if [ -z $1 ]; then echo "too few params"
  echo "usage \$1 = hub repo name"
  exit 1;
fi

required_env_vars=(GIT_USER GIT_TOKEN GIT_EMAIL DOCKER_USER DOCKER_PASS)
for evn in "${required_env_vars[@]}"
do
  if [ -v `echo $evn` ];
  then
    echo "$evn is set";
  else
    echo "$evn is required by deploy.sh but unset."; exit 1;
  fi
done

serviceName=$CIRCLE_PROJECT_REPONAME
echo "using serviceName = $serviceName"
repoPath=gr4per/azureswarm/develop
targetEnv=develop
if [[ "$CIRCLE_BRANCH" == "master" ]]; then
  repoPath=gr4per/azureswarm/master
  targetEnv=stage
fi
echo "using repoPath : $repoPath"

if [ -f "VERSION" ]
then
        echo "VERSION file: $(cat VERSION)"
else
  echo "VERSION file not found, exiting"
  exit 1
fi

export version=`cat VERSION`-dev-$CIRCLE_BUILD_NUM
if [[ "$CIRCLE_BRANCH" == "master" ]]
then
  export version=`cat VERSION`-rc-$CIRCLE_BUILD_NUM
fi
echo "version=$version"

curl https://raw.githubusercontent.com/$repoPath/public_ip.sh > public_ip.sh
chmod +x public_ip.sh
source public_ip.sh $targetEnv

if [[ "$?" > 0 ]]; then
  echo "error getting public ip for env $targetEnv, exiting"
fi
echo "public_ip=$public_ip, target_user=$target_user, logstash_ip=$logstash_ip"

echo "
---------------------
building docker image"
docker build -t $hub_repo:latest -t $hub_repo:dev .
if [[ "$?" > 0 ]]; then
  echo "error building docker image, exiting"
  exit 1
fi

echo "
-----------------------
local integration tests"
docker-compose up -d
monitor_docker() {
for attempt in {1..30}; do
  dop=$(docker ps | grep "build_main")
  echo $dop | grep -e "\(health: starting\)"
  if [[ "$?" > 0 ]]; then
    echo "health no longer in starting status"
  else
    echo "container starting, wait another few seconds"
    sleep 5
    continue
  fi
  echo $dop | grep -e "\(healthy\)"
  if [[ "$?" > 0 ]]; then
    echo "container not healthy after starting, failing build. container status:
$dop"
    exit 1
  else
    echo "container is healthy"
    return 0
  fi
done
  echo "Service startup took too long, failing build."
  return 1
}
monitor_docker
if [[ "$?" > 0 ]]; then exit 1; fi

echo "
-------------------
checking consul health now"

# we have to complicate this as due to docker in docker isolation the consul is not 
# reachable via host network exposed ports (docker0 not visible in CircleCi)
consul_id=$(docker ps | grep "_consul_" | awk '{print $1}')
echo "consul container id=$consul_id"
monitor_consul() {
for attempt in {1..5}; do
  consulOutput=$(docker exec -i -t $consul_id curl -f localhost:8500/v1/health/service/$serviceName)
  if [[ "$?" > 0 ]]; then
    echo "failed docker-compose integration test, not able to get health result from consul. curl returned $consulOutput"
    sleep 5
    continue
  fi
  integration_tests_result=$(echo $consulOutput | jq -e ".[].Checks|.[]|select(.ServiceName == \"$serviceName\" and .Status == \"passing\")")
  if [[ "$?" > 0 ]]; then
    serviceCheck=$(echo $consulOutput | jq -e ".[].Checks|.[]|select(.ServiceName == \"$serviceName\")")
    echo "failed docker-compose integration test, consul is not showing service as passing,
 current output: $serviceCheck"
    sleep 5
    continue
  else 
    echo "container passing consul health check"
    return 0
  fi
done
  echo "Consul health check not turning green in time, failing build"
  return 1
}
monitor_consul
if [[ "$?" > 0 ]]; then exit 1; fi

echo "
---------------------
preparing git for writing"
git config --global user.email "$GIT_EMAIL"
git config --global user.name "$GIT_USER"
git config --global credential.helper cache
newRemote=$(git config -l | grep "remote.origin.url=" | grep -o "git.*" | sed "s/git@github.com:/https:\/\/github.com\//g")
echo "setting remote url to $newRemote"
git remote set-url origin $newRemote
if [[ -f ~/.netrc ]]
then
  echo ".netrc exists, removing"
  rm ~/.netrc
fi

echo "machine github.com
login $GIT_USER
password $GIT_TOKEN
protocol https" > ~/.netrc

echo "
---------------------------------------
tagging commit $CIRCLE_SHA1 as $version"
git tag -a "$version" -m "$version"
git push --tags
if [[ "$?" > 0 ]]; then exit 1; fi

echo "
-----------------
push docker image"
docker login -u $DOCKER_USER -p $DOCKER_PASS
docker tag $hub_repo:latest $hub_repo:$version
docker push $hub_repo:$version
if [[ "$?" > 0 ]]; then 
  echo "pushing image failed, exiting..."
  exit 1
fi

echo "
-------------------------------
deploying service to $targetEnv"
curl https://raw.githubusercontent.com/$repoPath/deploy.sh > deploy.sh
chmod +x deploy.sh
./deploy.sh $target_user $public_ip $hub_repo $version $targetEnv $repoPath
if [[ "$?" > 0 ]]; then
  echo "deployment failed. exiting..."
  exit 1
fi

function run_integration_tests {
  if [[ ! -f integration_tests.sh ]]
  then
    curl https://raw.githubusercontent.com/$repoPath/integration_tests.sh > integration_tests.sh
    chmod +x integration_tests.sh
  fi

  echo "run integrations tests on $public_ip"
  ./integration_tests.sh $target_user $public_ip $CIRCLE_PROJECT_REPONAME
}
echo "
-----------------------
running integration tests"
run_integration_tests

if [[ "$CIRCLE_BRANCH" == "develop" ]]
then
  echo "
----------------------
push docker image :dev"
  docker push $hub_repo:dev

  echo "
-----------------------
merge develop to master"
  git push origin develop:master
fi

if [[ "$CIRCLE_BRANCH" == "master" && "$targetEnv" == "stage" ]]
then
  targetEnv=prod
  source public_ip.sh $targetEnv

  if [[ "$?" > 0 ]]; then
   echo "error getting public ip for env $targetEnv, exiting"
  fi
  echo "public_ip=$public_ip, target_user=$target_user, logstash_ip=$logstash_ip"

  version=`cat VERSION`

  ./deploy_service.sh $target_user $targetEnv $hub_repo $version $targetEnv $repoPath

  run_integration_tests

  echo "incrementing version from $version"
  curl https://raw.githubusercontent.com/fsaintjacques/semver-tool/master/src/semver > semver.sh
  chmod +x semver.sh
  git branch develop
  bumped_version=$(./semver.sh bump patch $version)
  $bumped_version > VERSION
  git add -A
  git commit -m "$bumped_version [ci skip]"
  git tag -a "$bumped_version" -m "$bumped_version"
  git push
  git push --tags
fi
