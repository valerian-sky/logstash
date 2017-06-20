#!/bin/bash

get_multiple_options_from_array() {
  #desired_val=$(jq --join-output ".production+.default|.[\"`echo $1`\"]|\" --`echo $1` \"+.[]" task_template_mapped.json)
  json_val=$(jq "if (.$targetEnv|has(\"`echo $1`\")) then .$targetEnv|.[\"`echo $1`\"] else .default|.[\"`echo $1`\"] end" task_template_mapped.json)
  echo "json=$json_val"
  desired_val=$(echo $json_val | jq --join-output "\"\"+.[]|\" --`echo $1` \" + if (index(\" \") > -1 and index(\"\\\"\") < 1) then \"\\\"\"+.+\"\\\"\" else . end")
  echo "desired=$desired_val"
  if [[ -z "$desired_val" ]]
  then
    echo "no desired new value, skipping $1"
  else
    docker_cmd=$docker_cmd$desired_val
  fi
  
}
get_multiple_options_from_string() {
  json_val=$(jq "if (.$targetEnv|has(\"`echo $1`\")) then .$targetEnv|.[\"`echo $1`\"] else .default|.[\"`echo $1`\"] end" task_template_mapped.json)
  echo "json=$json_val"
  desired_val=$(echo $json_val | jq --join-output "\" --`echo $1` \" + if (index(\" \") > -1 and index(\"\\\"\") < 1) then \"\\\"\"+.+\"\\\"\" else . end")
  echo "desired=$desired_val"
  if [[ -z "$desired_val" ]]
  then
    echo "no desired new value, skipping $1"
  else 
    docker_cmd=$docker_cmd$desired_val
  fi
}


build_docker_create() {
  docker_cmd="docker service create --secret=\"$1\""
  # iterating all params that we want (project source)
  for x in $wanted_params
  do
    if ! jq -e ".[\"$x\"]" field_defs.json > /dev/null
    then
      echo "param $x not supported"
      #exit 1
    fi
    #echo $x $?
    field_def=$(jq ".[\"`echo $x`\"]" field_defs.json)
    #echo $field_def
    field_type=$(echo $field_def | jq ".type" | sed -e "s/\"//g")
    case $field_type in
    mart)
      echo "$x is mart"
      get_multiple_options_from_array $x
      ;;
    mark)
      echo "$x is mark"
      get_multiple_options_from_array $x
      ;;
    mar)
      echo "$x is mar"
      get_multiple_options_from_array $x
      ;;
    repl)
      echo "$x is repl"
      #docker_cmd="$docker_cmd$desired_val"
      get_multiple_options_from_string $x
      ;;
    frepl)
      echo "$x is frepl"
      get_multiple_options_from_array $x
      ;;
    create)
      echo "$x is create"
      get_multiple_options_from_string $x
      ;;
    *)
      echo "it is $field_type and not matching any case"
      #exit 1
      ;;
    esac
  done
}

update_mar() {
  #desired_value is a json array
  #current_value is similar json array
  # for-each element in current_value but not in desired_value: --constraint-rm
  if [ "$current_value" = null ] ; then echo "current_value null, skipping"; else
    loop_var=$(echo $current_value | jq --join-output "\"\\\"\"+.[]+\"\\\" \"")
    echo "loop var = $loop_var"
    loop_count=$(echo $current_value | jq "length")
    for cin in `seq 1 $loop_count`
    do
      cv=$(echo $current_value | jq ".[$cin-1]")
      echo "for-loop cv = $cv"
      if ! echo $desired_value | jq -e "index([$cv])" > /dev/null
      then
        echo "param current_value $cv not required anymore by $desired_value, removing"
        docker_cmd="$docker_cmd  --$x-rm $cv"
        #exit 1
      else 
        echo "param current_value $cv still required by $desired_value, keeping"
      fi
    done
  fi
  
  if [ "$desired_value" = null ] ; then echo "desired_value null, skipping"; else
    # for-each element in desired_value but not in current_value: --constraint-add
    loop_var=$(echo $desired_value | jq --join-output "\"\\\"\"+.[]+\"\\\" \"")
    echo "loop var = $loop_var"
    loop_count=$(echo $desired_value | jq "length")
    for cin in `seq 1 $loop_count`
    do
      cv=$(echo $desired_value | jq ".[$cin-1]")
      echo "for-loop cv = $cv"
      if ! echo $current_value | jq -e "index([$cv])" > /dev/null
      then
        echo "param desired_value $cv not yet in $current_value, adding"
        docker_cmd="$docker_cmd --$x-add $cv"
        #exit 1
      else 
        echo "param desired_value $cv already covered by $current_value, keeping"
      fi
    done
  fi
}

update_mark() {
  #desired_value is a json array
  #current_value is similar json array
  # for-each element in current_value but not in desired_value: --constraint-rm
  if [ "$current_value" = null ] ; then echo "current_value null, skipping"; else
    loop_var=$(echo $current_value | jq --join-output ".[]|split(\"=\")[0]+\" \"")
    loop_count=$(echo $current_value | jq "length")
    for cin in `seq 1 $loop_count`
    do
      ck=$(echo $current_value | jq --raw-output ".[$cin-1]|split(\"=\")[0]")
      cv=$(echo $current_value | jq --raw-output ".[$cin-1]|ltrimstr(\"$ck=\")")
      echo "for-loop ck = $ck"
      echo "for-loop cv = $cv"
      #if ! echo $desired_value | jq -e "index([$cv])" > /dev/null
      din=$(echo $desired_value | jq -e "[.[]|split(\"=\")[0]]|index(\"$ck\")")
      echo "exit = $?, for-loop din = $din"
      if [ $din == null ]
      then
        echo "key $ck not required anymore by $desired_value, removing"
        docker_cmd="$docker_cmd --$x-rm $ck"
      else 
        echo "key current_value $ck still required by $desired_value, checking value"
        dv=$(echo $desired_value | jq -e --raw-output ".[$din]|ltrimstr(\"$ck=\")")
        if [ "$cv" = "$dv" ] ; then
          echo "old value $cv = desired value $dv, skipping"
        else
          echo "old value $cv != desired value $dv, updating"
          docker_cmd="$docker_cmd --$x-rm $ck"
          docker_cmd="$docker_cmd --$x-add $ck=$dv"
        fi
      fi
    done
  fi
  
  if [ "$desired_value" = null ] ; then echo "desired_value null, skipping"; else
    # for-each element in desired_value but not in current_value: --constraint-add
    loop_var=$(echo $desired_value | jq --join-output ".[]|split(\"=\")[0]+\" \"")
    loop_count=$(echo $desired_value | jq "length")
    for cin in `seq 1 $loop_count`
    do
      ck=$(echo $desired_value | jq --raw-output ".[$cin-1]|split(\"=\")[0]")
      cv=$(echo $desired_value | jq --raw-output ".[$cin-1]|ltrimstr(\"$ck=\")")
      echo "for-loop cv = $cv"
      echo "for-loop ck = $ck"
      din=$(echo $current_value | jq -e --raw-output "[.[]|split(\"=\")[0]]|index(\"$ck\")")
      echo "exit = $?, for-loop din = $din"
      if [ $din == null ]
      then
        echo "key $ck not yet in $current_value, adding"
        docker_cmd="$docker_cmd --$x-add $ck=$cv"
      else 
        echo "param desired_value $ck=$cv already covered by $current_value, keeping"
      fi
    done
  fi
}

update_mart() {
  #desired_value is comma separated list of key=value pairs, need to convert to json first
  json_desired_value=$(echo $desired_value | jq -e "[.[]|split(\",\")|[.[]|split(\"=\")]|map({key: (.[0]|explode |if 97 <= .[0] and .[0] <= 122 then .[0]=.[0]-32 else empty end|  implode), value: .[1]})]|[.[]|from_entries]")
  echo "json_desired_value = $json_desired_value"
  keyNames=$(echo $field_def|jq ".keyNames")
  echo "keyNames = $keyNames"
  mapCondition="."
  fieldMap=$(echo $field_def |jq -e ".fieldMap")
  if [[ "$?" > 0 ]]
  then
    echo "fieldmap empty: $fieldMap"
  else
    echo "fieldmap not empty: $fieldMap"
    mapCondition=$(echo $fieldMap | jq --raw-output "(to_entries|map(\"if .key == \\\"\" + .key + \"\\\" then .key = \\\"\" + .value + \"\\\" else \")|join(\"\")) + \".key = .key \" +(map(\"end\")|join(\" \"))")
  fi
  echo "mapCondition = $mapCondition"  

  keyFilter=$(echo $keyNames | jq --raw-output "map(\".key == \\\"\" + . + \"\\\"\")|join(\" or \")")
  echo "keyFilter = $keyFilter"

  mapped_json_desired_value=$(echo $json_desired_value | jq "map(with_entries($mapCondition))")
  echo "mapped_json_desired_value = $mapped_json_desired_value"
  #current_value is similar json array
  # for-each element in current_value but not in desired_value: --constraint-rm
  if [ "$current_value" = null ] ; then echo "current_value null, skipping"; else
    loop_count=$(echo $current_value | jq "length")
    for cin in `seq 1 $loop_count`
    do
      #ck=$(echo $current_value | jq --raw-output ".[$cin-1]|.Target")
      cv=$(echo $current_value | jq --raw-output --sort-keys ".[$cin-1]|to_entries|map(.value = (.value|tostring))|from_entries")
      keyCondition=$(echo $cv | jq --raw-output "[to_entries|.[]|[select($keyFilter)]|from_entries]|add|to_entries|[.[]|\"(.\"+.key+\"|tostring) == \\\"\"+(.value|tostring)+\"\\\"\"]|join(\" and \")")
      # this is the key used for --<property>-rm 
      rmKeyType=$(echo $field_def|jq -e --raw-output ".rmKeyType")
      if [[ "$?" > 0 ]]
      then
        echo "rmKeyType empty"
        keyFormatter=$(echo $keyNames | jq --raw-output "map(\"(.\" + . + \"|tostring)\")|join(\"+\\\"/\\\"+\")")
      else
        echo "rmKeyType not empty: $rmKeyType"
        case $rmKeyType in
        srcKVCommaSeparated)
          echo "rmKeyFormatter is srcKVCommaSeparated"
          keyFormatter=$(echo $keyNames | jq "($fieldMap|to_entries|map({(.value):.key})|add) as \$reverseMap|$cv as \$cv|[.[]|. as \$x|(if (\$reverseMap|.[\$x]) then (\$reverseMap|.[\$x]) else . end)|ascii_downcase+\"=\"+(\$cv|.[\$x])]|join(\",\")")
          ;;
        *)
          echo "rmKeyFormatter \"$rmKeyType\" is not supported"
          exit 1
          ;;
        esac
      fi
      ck=$(echo $cv | jq "$keyFormatter")
      echo "current_value for-loop formattedKey = $ck"
      echo "current_value for-loop cv = $cv"
      echo "current_value for-loop keyCondition = $keyCondition"
      #if ! echo $desired_value | jq -e "index([$cv])" > /dev/null
       
      din=$(echo $mapped_json_desired_value | jq -e "index(.[]|select($keyCondition))")
      if [[ "$?" > 0 ]] #[ $din == null ]
      then
        echo "key $ck not required anymore by $desired_value, removing"
        docker_cmd="$docker_cmd --$x-rm $ck"
        echo "docker_cmd=$docker_cmd"
      else 
        echo "din = $din"
        echo "key current_value $ck still required by $desired_value, checking value"
        dv=$(echo $mapped_json_desired_value | jq -e --sort-keys --raw-output ".[$din]")
        if [ "$cv" = "$dv" ] ; then
          echo "old value $cv = desired value $dv, skipping"
        else
          echo "old value $cv != desired value $dv, updating"
          docker_cmd="$docker_cmd --$x-rm $ck"
          dvof=$(echo $desired_value| jq --raw-output ".[$din]") # dseired_value and mapped_json_desired_value have same array order
          docker_cmd="$docker_cmd --$x-add $dvof"
          echo "docker_cmd=$docker_cmd"
        fi
      fi
    done
  fi

  if [ "$desired_value" = null ] ; then echo "desired_value null, skipping"; else
    # for-each element in desired_value but not in current_value: --constraint-add
    loop_count=$(echo $desired_value | jq "length")
    for cin in `seq 1 $loop_count`
    do
      cv=$(echo $mapped_json_desired_value | jq --raw-output ".[$cin-1]")
      echo "desired_value for-loop cv = $cv"
      keyCondition=$(echo $cv | jq --raw-output "[to_entries|.[]|[select($keyFilter)]|from_entries]|add|to_entries|[.[]|\"(.\"+.key+\"|tostring) == \\\"\"+(.value|tostring)+\"\\\"\"]|join(\" and \")")
      ck=$(echo $cv | jq "$keyFormatter")
      echo "desired_value for-loop ck = $ck"
      din=$(echo $current_value | jq -e "index(.[]|select($keyCondition))")
      #echo "exit = $?, for-loop din = $din"
      if [[ "$?" > 0 ]]
      then
        echo "key $ck not yet in $current_value, adding"
          dvof=$(echo $desired_value| jq --raw-output ".[$cin-1]")
          #echo "dvof=$dvof"
          docker_cmd="$docker_cmd --$x-add $dvof"
          echo "docker_cmd=$docker_cmd"
      else 
        echo "param desired_value $ck=$cv already covered by $current_value, keeping"
      fi
    done
  fi
}

build_docker_update() {
  docker_cmd="docker service update"
  supported_params=$(jq 'keys|@sh' field_defs.json | sed -e "s/\"//g" | sed -e "s/'//g")  
  echo "looping supported: $supported_params"
  # iterating all params that we want (project source)
  for x in $supported_params
  do
    # find current value
    field_def=$(jq ".[\"`echo $x`\"]" field_defs.json)
    echo "field_def $field_def"
    val_type=$(echo $field_def | jq --raw-output ".type")
    echo "val_type $val_type"
    val_path=$(echo $field_def | jq --raw-output ".path" | sed -e "s/\//./g")
    echo "val_path $val_path"
    current_value=$(jq ".[0].`echo $val_path`" service_config_clean.json)
    echo "current: $current_value"
    desired_value=$(jq "if (.$targetEnv|has(\"`echo $x`\")) then .$targetEnv|.[\"`echo $x`\"] else .default|.[\"`echo $x`\"] end" task_template_mapped.json)
    echo "desired: $desired_value"
    #echo $field_def
    #field_type=$(echo $field_def | jq ".type" | sed -e "s/\"//g")
    if [ "$desired_value" == "null" ]; then echo "skipping as there is no desired value" && continue; fi
    case $val_type in
    mart)
      echo "$x is mart"
      update_mart
      ;;
    mark)
      echo "$x is mark"
      update_mark
      ;;
    mar) #e.g. constraint
      echo "$x is mar"
      update_mar
      ;;
    repl)
      
echo "$x is repl"
      get_multiple_options_from_string $x
      ;;
    frepl)
      echo "$x is frepl"
      get_multiple_options_from_array $x
      ;;
    update)
      echo "$x is update"
      ;;
    create)
      echo "$x is create, skipping"
      ;;
    *)
      echo "it is $field_type and not matching any case"
      exit 1
      ;;
    esac

  done
  docker_cmd="$docker_cmd --force --image"
}
