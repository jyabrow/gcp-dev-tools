#!/bin/bash

appname=`basename "$0"`
actions=(list deploy purge)
action_vals="$(echo ${actions[@]} | sed 's/ /, /g')"
action=''
action_arg=''
bucket='gs://live-app-repo-us'
vm_name=''
vm_name_default='ln-buildtest-01'
vm_zone='us-east4-b'
dry_run='echo'
status=0

usage() {
    echo "$appname - script to list or deploy Live property model(s) on GCP VM"
    echo ""
    echo "This script helps manage and deploy bvc Live 3D property models,"
    echo "providing an easy way of installing them on a GCP VM for testing and"
    echo "publishing.  A property model is a compressed file that contains all"
    echo "of the model and support files needed for live-app to load and render"
    echo "the property in full streaming real-time 3D."
    echo ""
    echo "usage: $appname <action> [arg] [options]"
    echo ""
    echo "action - One of the following keywords:"
    echo "    list   - List all property models (in GS bucket or on VM)"
    echo "    deploy <file> - Deploy a property model file to a staging VM"
#    echo "    purge  <id>   - Delete old models, retaining N most recent ones"
    echo ""
    echo "options - any of the following:"
    echo "   -b,--bucket <name>  - Name of G-Storage bucket (default=$bucket)"
    echo "   -v,--vm <name>      - Name of destination VM, default=$vm_name_default"
    echo "   -z,--zone <name>    - Availability zone of the VM, (default=$zone)"
    echo "   -d,--dry-run    - Print all commands, but do not execute (default)"
    echo "   -f,--force      - Override --dry-run default and execute commands"
    echo "   -h,--help       - Print this help info"
    echo ""
    echo "examples:"
    echo ""
    echo "    # Print all models in $bucket"
    echo "    $appname list"
    echo ""
    echo "    # Print all models on $vm_name_default"
    echo "    $appname list -v $vm_name_default"
    echo ""
    echo "    # Deploy models from G-Storage to VM"
    echo "    $appname deploy gs://JF0FT0AdOJWvmTfvubYW-healthpeak_100acorndrive_cambridge-cs80-20230223-100649.7z"
    echo ""
#    echo "    # Purge all but last 3 models from G-Storage"
#    echo "    $appname purge 3"
#    echo ""
}

# Parse command line arguments
#
while [ -n "$1" ]
do
    case $1 in
        -b|--bucket) bucket_name=$2; shift 2;;
        -v|--vm) vm_name=$2; shift 2;;
        -z|--zone) vm_zone=$2; shift 2;;
        -d|--dry-run) dry_run="echo"; shift;;
		-f|--force) dry_run=""; shift;;
        -?|-h|--help|help) usage; exit 0;;
        -*) echo "$appname: error, unknown option '$1', see --help for usage"; exit 1;;
        *)  if [ -z "$action" ]; then
                if [[ " ${actions[*]} " =~ " $1 " ]]; then
                    action=$1
                else
                    echo "$appname: error, bad action '$1', expecting one of $action_vals"
                    exit 1
                fi
            else
                action_arg=$1
            fi
            shift;;
    esac
done

zspec="--zone $vm_zone"

parse_model_filename () {
    # Argument $1: expecting gs://<property-id>-<repo-name>-<cs#>-<timestamp>.7z
    archive_name=$(basename -- "$1")
    model_name="${archive_name%.*}"
    IFS='-' read -ra parts <<< "$model_name"
    property_id=${parts[0]}
    repo_name=${parts[1]}
    changeset=${parts[2]}
    local build_date="${parts[3]}"
    local build_time="${parts[4]}"
    timestamp="${build_date}-${build_time}"
}

get_current_vm_model () {
    # Get model link and folder name, if previous version already exists
    #
    echo "$appname: looking for previous model $property_id on $vm_name..."
    curr_model_ls=`gcloud compute ssh bvw_admin@$vm_name $zspec --command "cd builds && ls -ld $property_id"` || true
    # expecting something like: 
    # lrwxrwxrwx 1 bvw_admin 197121 47 Mar 1 00:34 JF0FT0AdOJWvmTfvubYW -> bvw-JF0FT0AdOJWvmTfvubYW-cs80-20230223-100649
    if [ -n "$curr_model_ls" ]; then
        IFS=' ' read -ra parts <<< "$curr_model_ls"
        curr_model_folder="${parts[${#parts[@]}-1]}"
        echo "$appname: removing previous model on $vm_name, $curr_model_folder"
        [[ $dry_run != "echo" ]] && set -x
        $dry_run gcloud compute ssh bvw_admin@$vm_name $zspec --command "cd builds && rm -rf $curr_model_folder"
        { status=$?; set +x; } 2>/dev/null
    fi
}

set -e    # Exit upon first failed command

if [ -z "$action" ]; then
    echo "$appname: error, missing action argument, see --help for usage"
    exit 1
fi

if [[ $action == "list" ]]; then
    if [ -z "$vm_name" ]; then
        set -x
        gsutil ls -l $bucket/${action_arg}*
        exit $?
    else
        set -x
        gcloud compute ssh bvw_admin@$vm_name $zspec --command "cd builds && ls -l"        
        exit $?
    fi
fi

if [ -z "$vm_name" ]; then
    # If vm_name not supplied and if not in list mode, set default vm
    vm_name=$default_vm
fi

if [ -z "$action_arg" ]; then
    echo "$appname: error, missing argument for action=$action, see --help for usage"
    exit 1
fi

if [[ $dry_run == "echo" ]]; then
	echo ""
	echo "$appname: this is a DRY RUN, commands are printed, not executed"
	echo ""
fi

if [[ $action == "deploy" ]]; then
    parse_model_filename "$action_arg"
    echo "$appname: deploy vm=$vm_name, zone=$vm_zone, model=$action_arg"
    get_current_vm_model
    # If not --dry-run mode, turn on trace mode
    [[ $dry_run != "echo" ]] && set -x
    # Download model archive, unzip, replace link, remove model archive file
    $dry_run gcloud compute ssh bvw_admin@$vm_name $zspec --command "cd builds && gsutil cp $action_arg ."
    $dry_run gcloud compute ssh bvw_admin@$vm_name $zspec --command "cd builds && 7z x $archive_name"
    $dry_run gcloud compute ssh bvw_admin@$vm_name $zspec --command "cd builds && rm -f $property_id"
    $dry_run gcloud compute ssh bvw_admin@$vm_name $zspec --command "cd builds && mklink /d $property_id $model_name"
    $dry_run gcloud compute ssh bvw_admin@$vm_name $zspec --command "cd builds && rm -r $archive_name"
    # TODO: remove previous model (how to get prev model name?)
    { status=$?; set +x; } 2>/dev/null
fi

if [[ $action == "purge" ]]; then
    echo "$appname: error, purge not implemented yet"
    exit 1
fi

if [[ $dry_run == "echo" ]]; then
	echo ""
	echo "$appname: end of DRY RUN, to execute use the -f (--force) option"
	echo ""
	echo "$appname: for more info, use --help option"
fi

exit $status
