#!/bin/bash

set -e

# install latest cf cli
sudo wget -O /tmp/cfcli.deb "https://cli.run.pivotal.io/stable?release=debian64&version=6.22.2&source=github-rel"  > /dev/null 2>&1
sudo dpkg -i /tmp/cfcli.deb && apt-get install -f  > /dev/null 2>&1

# Functions

function fn_auth_cli {

  cf api ${cf_api} --skip-ssl-validation > /dev/null 2>&1
  cf login -u ${cf_user} -p ${cf_password} -o system -s system > /dev/null 2>&1

}

function fn_get_buildpack_id {

   local buildpack=${1}

   my_cmd="cf curl /v2/buildpacks | jq '.resources[] | select(.entity.name==\"${buildpack}\") | .' | jq .metadata.guid | tr -d '\"'"
   eval $my_cmd

}

function fn_restage_apps_with_buildpack {

  echo "Starting Healthcheck Jobs ..."

  #let "FAIL=0"

  local buildpack_id=${1}
  declare -a apps
  my_cmd="cf curl /v2/apps | jq '.resources[] | select(.entity.detected_buildpack_guid==\"${buildpack_id}\") | .metadata.guid' | tr -d '\"'"
  apps=$(eval $my_cmd)
  for x in ${apps[@]}; do
      echo "Restaging ${x}"
      cf curl -X POST /v2/apps/$x/restage > /dev/null 2>&1
      $PWD/concourse-day2-buildpacks/ci/tasks/update/fn_healthcheck.sh $x &
  done

  echo "Wating for Healthcheck Jobs to finish ..."

  for my_job in $(jobs -p); do
    echo "wait:$my_job"
    wait $my_job #let "FAIL+=1"
  done

  if [ $FAIL -gt 0 ]; then
      echo "FAIL"$FAIL
  else
      echo "All Apps with buildpack ${buildpack} have sucessfully restaged"
      exit 0
  fi
}


function fn_trigger {

  declare -a apps
  echo "Will work on ... ${buildpack}"
  fn_auth_cli
  buildpack_id=$(fn_get_buildpack_id "${buildpack}")
  fn_restage_apps_with_buildpack "${buildpack_id}"

}


# Main Logic
case ${buildpack} in
    java_buildpack_offline)
      fn_trigger
      ;;
    go_buildpack)
      fn_trigger
      ;;
    nodejs_buildpack)
      fn_trigger
      ;;
    *)
      echo "BuildPack ${buildpack} Not Yet Instrumented!!!"
      exit 1
      ;;
esac
