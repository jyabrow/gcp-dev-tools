#!/bin/bash
#
# Script to create and view GCP templates

appname=`basename "$0"`
gpumodel='T4'
environment="staging"
env_vals="'staging' or 'production'"
project="bvc-portal-staging"
template_name=""

usage() {
    echo "$appname - script to view GCP instance templates"
    echo ""
    echo "This script lists the GCE instance templates used by bvc"
    echo "services, and can also print individual template details. It is"
    echo "basically a convenient wrapper for more complex gcloud commands,"
    echo "It will print the exact verbose gcloud commands executed to perform"
    echo "the operations."
    echo ""
    echo "Instance Templates define the VM configuration of attributes such as"
    echo "cpu, ram, gpu, image, (and many others) used when VMs are created."
    echo "They are typically created from the GCP console (too complex for the"
    echo "command line)."
    echo ""
    echo ""
    echo "usage: $appname <action> <template> [options]"
    echo ""
    echo "action - One of the following keywords:"
    echo ""
    echo "    list        - List all custom templates in staging"
    echo "    describe    - Get detailed information about an instance template"
    echo ""
    echo "template - A template name, use 'list' action to get template names"
    echo ""
    echo "options"
    echo ""
    echo "   -e,--env   - Keyword, one of: $env_vals (default: $environment)"
    echo "   -h,--help  - Print this help info"
    echo ""
    echo "examples:"
    echo ""
    echo "    $appname list             -  prints list of existing templates"
    echo "    $appname describe <name>  -  prints detailed description of template"
    echo ""
}

while [ -n "$1" ]
do
    case $1 in
        -e|--env|--environment)
            case $2 in
                 staging) project="bvc-portal-staging"; shift 2;;
                 production) project="bvc-portal"; shift 2;;
                 *) echo "$appname: error, bad --env value, '$2', expecting $env_vals"; exit 1;;
            esac;;
        -?|-h|--help|help) usage; exit 0;;
        -*) echo "$appname: error, unknown option '$1', see --help for usage"; exit 1;;
        list)
            action="list"; shift;;
        describe)
            action="describe"
            template_name="$2"; shift 2
            if [[ -z "$template_name" ]]; then
                echo "$appname: error, missing template name argument for action '$action'"
                exit 1
            fi;;
        *) echo "$appname: error, unknown action '$1', see --help for usage"
           exit 1;;
    esac
done

if [[ -z "$action" ]]; then
    echo "$appname: error, missing action argument, see --help for usage"
    exit 1
fi

set -x
gcloud compute instance-templates $action $template_name --project $project
exit $?