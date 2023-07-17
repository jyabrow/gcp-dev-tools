#!/bin/bash
#
# VM instance management script for bvc Live service
#

# Argument & option defaults
#
appname=`basename "$0"`
actions=(list create stop start delete templates)
action_vals="$(echo ${actions[@]} | sed 's/ /, /g')"
environment="staging"
env_vals="'staging' or 'production'"
project="bvc-portal-staging"
vm_zone_default="us-east4-b"
template="livenode-8-cpu-t4-gpu"
labels="client=bvc"
dry_run="echo"


usage() {
    echo "$appname - bvc VM instance management script"
    echo ""
    echo "This script manages Live Node GCP vm instances, enabling manual"
    echo "and scripted deployment testing, with control over basic VM"
    echo "settings, such as name, zone, template, and environment.  It is"
    echo "basically a convenient wrapper for GCP 'gcloud compute' commands,"
    echo "which are printed exactly as executed."
    echo ""
    echo "usage: $appname <action> [<vms>] [options]"
    echo ""
    echo "   <action>   - Keyword, one of: $action_vals"
    echo "   <vms>      - One or more vm names (see examples below)"
    echo ""
    echo "   -e,--env   - Keyword, one of: $env_vals (default: $environment)"
    echo "   -z,--zone  - VM zone name (see below) or keyword 'any', (default=$vm_zone_default)"
    echo "   -t,--template - Name of template to use (default: $template)'"
    echo "   -l,--labels - CSV list of labels (default: '$labels')"
    echo "   -d,--dry-run  - Print all commands, but do not execute (default)"
    echo "   -f,--force - Execute create or publish (opposite of --dry-run)"
    echo "   -h,--help  - Print this help info"
    echo ""
    echo "examples:"
    echo ""
    echo "   $appname list"
    echo "   $appname create ln-test-01 ln-test-02 --zone us-west2-a"
    echo "   $appname create ln-test-01 -f"
    echo "   $appname stop ln-test-02 --zone us-west2-a"
    echo "   $appname start ln-test-02 --zone us-west2-a"
    echo "   $appname delete ln-test-01 ln-test-02 --dry-run"
    echo ""
    echo "zones: https://cloud.google.com/compute/docs/gpus/gpu-regions-zones"
    echo ""
    echo "bvc VM's are configured with a GPU, which is necessary to"
    echo "provide real-time 3D rendering. The above URL lists the zones that"
    echo "have available GPUs.  Make sure to only use those zones, see also"
    echo "bvzones.sh"
    echo ""
}


# Process arguments & options
#
action=""
vms=()
while [ -n "$1" ]
do
    case $1 in
        -e|--env|--environment)
            case $2 in
                 staging) project="bvc-portal-staging"; shift 2;;
                 production) project="bvc-portal"; shift 2;;
                 *) echo "$appname: error, bad --env value, '$2', expecting $env_vals"; exit 1;;
            esac;;
        -z|--zone) ui_zone=$2; shift 2;;
        -t|--template) template=$2; shift 2;;
        -l|--labels) labels=$2; shift 2;;
        -d|--dry-run) dry_run="echo"; shift;;
        -f|--force) dry_run=""; shift;;
        -h|--help|help) usage; exit 0;;
        -*) echo "$appname: error, unknown option '$1', cannot proceed"; exit 1;;
        *)  if [ -z "$action" ]; then
                if [[ " ${actions[*]} " =~ " $1 " ]]; then
                    action=$1
                else
                    echo "$appname: error, bad action '$1', expecting one of $action_vals"
                    exit 1
                fi
            else
                vms+=($1)
            fi
            shift;;
    esac
done

# Construct commands and perform action
#
if [ -z "$action" ]; then
    echo "$appname: error, missing action arg, see -help for usage"
    exit 1
fi

if [[ $action == "list" ]]; then
    set -x
    gcloud compute instances list \
    --project $project \
    --format="table(name,zone,machineType,networkInterfaces[0].accessConfigs[0].natIP,status,lastStartTimestamp,labels)"
    exit $?
fi

if [[ $action == "templates" ]]; then
    set -x
    gcloud compute instance-templates list --project $project
    exit $?
fi

if [ ${#vms[@]} -eq 0 ]; then
    echo "$appname: error, missing vm name(s), see --help for usage"
    exit 1
fi

template_spec=""
label_spec=""
if [[ $action == "create" ]]; then
    template_spec="--source-instance-template $template"
    label_spec="--labels $labels"
fi

# Get existing VM instance info (use first one in list)
gc_zone=`gcloud compute instances list --filter="name=${vms[0]}" --project $project --format "get(zone)" | awk -F/ '{print $NF}'`
if [ -z "$gc_zone" ]; then
    # First vm name in input list not found, use default vm_zone
    vm_zone=$vm_zone_default

    # If there was no matching vm name (no zone), start, stop, delete are disallowed
    case "$action" in
        start|stop|delete)
            echo "$appname: error, existing GCP VM ${vms[0]} not found, cannot perform $action"
            exit 1;;
    esac
else
    vm_zone=$gc_zone
fi

zone_spec="--zone $vm_zone"

if [[ $dry_run == "echo" ]]; then
	echo ""
	echo "$appname: this is a DRY RUN, commands are printed, not executed"
	echo ""
fi

# If not --dry-run mode, turn on trace mode
[[ $dry_run != "echo" ]] && set -x

$dry_run gcloud compute instances $action ${vms[@]} \
    --project $project \
    $template_spec \
    $zone_spec \
    $label_spec \
    --quiet

# Turn off trace mode, retain status while avoiding trace off echo, taken from:
# https://stackoverflow.com/questions/13195655/bash-set-x-without-it-being-printed
{ status=$?; set +x; } 2>/dev/null

if [[ $dry_run == "echo" ]]; then
	echo ""
	echo "$appname: end of DRY RUN, to execute use the -f (--force) option"
	echo ""
	echo "$appname: for more info, use --help option"
fi


exit $status