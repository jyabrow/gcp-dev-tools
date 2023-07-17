#!/bin/bash

# Script to create or publish new live-node image, based on existing vm disk

appname=`basename "$0"`

usage() {
    echo "$appname - script to create or publish new live-node image"
    echo ""
    echo "This script creates a new GCE VM custom image in staging environment,"
    echo "or publishes an existing image from staging to production. A custom"
    echo "staging image is made from an existing live-node VM that is shut down."
    echo "A production image is simply a copy of the latest image from staging."
    echo ""
    echo "Images are named according to the SCM tracking id (commit sha) of the"
    echo "live-node code on the source VM, (plus for now, property id's)."
    echo ""
    echo "When a new staging image is created, it is copied to a default name:"
    echo "'livenode-latest', which is used by all VM templates, ensuring that"
    echo "newly provisioned VMs always use the latest image."
    echo ""
    echo "example: livenode-06062e7-5343-5477-5540-5548 (=> livenode-latest)"
    echo ""
    echo "usage: $appname <action> [options]"
    echo ""
    echo "   action - One of the following keywords:"
    echo ""
    echo "       list        - List all custom images in staging & production"
    echo "       create      - Create new image in staging"
    echo "       delete      - Create new image in staging"
    echo "       publish     - Copy staging image to production"
    echo ""
    echo "   Options"
    echo "   --vm, --vm-name - Name of source image VM (create only), default=$vm_name"
    echo "   --im, --im-name - Name of source image, (for delete & publish only)"
    echo "   -z, --zone      - Availability zone of the VM, default=us-east4-b"
    echo "   --livenode-sha  - Live-node SCM tracking string (live-node commit sha)"
    echo "   --liveapp-sha   - Live-app SCM tracking string (live-app commit sha)"
    echo "   --scm-bvw     - bvw-Unity tracking string (PlasticSCM changeset #'s)"
    echo "   -d,--dry-run    - Print all relevant info, but do not execute (default)"
    echo "   -f,--force      - Override --dry-run default and execute commands"
    echo "   -h,--help       - Print this help info"
    echo ""
    echo "examples:"
    echo ""
    echo "   # To view gcloud commands and default args for image create:"
    echo "       ./$appname create"
    echo ""
    echo "   # To create a staging image from livenode-02 vm in us-west2-a zone"
    echo "       ./$appname create --vm livenode-02 --zone us-west2-a -f"
    echo ""
    echo "   # To view gcloud commands and default args for image publish "
    echo "       ./$appname publish --dry-run"
    echo ""
    echo "   # To list images in staging and production"
    echo "       ./$appname list"
    echo ""
    echo "   # To publish latest image from staging to production"
    echo "       ./$appname publish --im livenode-latest -f"
    echo ""
    echo "   # To delete a staging image"
    echo "       ./$appname delete --im livenode-06062e7-5343-5477-5540-5548 -f"
    echo ""
}

validate_image_name() {
    if [[ -z "$image_name" ]]; then
        echo "$appname: error, missing image name, specify with --im option"
        echo "$appname: (also, use 'list' command to show image names)"
        echo ""
        exit 1
    fi
}

# Set defaults
#
set +x
action="nothing"
vm_name="ln-buildtest-01"
vm_zone="us-east4-b"
dry_run="echo"

# Set default SCM tracking info
#
livenode_commit_sha=""
liveapp_commit_sha=""

#TODO: if no arguments or if -h|--help, print usage


# First argument is action keyword
#
action=$1; shift
case $action in
	create) echo "$appname: creating new staging image";;
    delete) echo "$appname: deleting staging image";;
	publish) echo "$appname: publishing staging image to production";;
	list) echo "$appname: listing images for staging & production";;
	-h|--help) usage; exit 0;;
	"") echo "$appname: error, missing action arg, '$action', expecting 'list', 'create' or 'publish'"
	    usage
	    exit 1;;
	*) echo "$appname: error, bad action arg, '$action', expecting 'list', 'create' or 'publish'"
	   exit 1;;
esac

# Process additional arguments
#
while [ -n "$1" ]
do
    case $1 in
        --vm|--vm-name) vm_name=$2; shift 2;;
        --im|--im-name) image_name=$2; shift 2;;
        -z|--zone) vm_zone=$2; shift 2;;
        --livenode-sha) livenode_commit_sha=$2; shift 2;;
        --liveapp-sha) liveapp_commit_sha=$2; shift 2;;
        --scm-bvw) liveapp_commit_sha=$2; shift 2;;
        -d|--dry-run) dry_run="echo"; shift;;
		-f|--force) dry_run=""; shift;;
        -h|--help) usage; exit 1;;
        *) echo "$appname: error, unknown argument '$1', proceed"; exit 1;;
    esac
done

if [[ $action == "list" ]]; then
    echo ""
    set -x
    gcloud compute images list --no-standard-images --project bvc-portal-staging \
        --format="table(name,description,diskSizeGb,archiveSizeBytes,creationTimestamp)" \
        --sort-by=creationTimestamp
    ( echo "" ) 2>/dev/null # Silently disable xtrace
    gcloud compute images list --no-standard-images --project bvc-portal \
        --format="table(name,description,diskSizeGb,archiveSizeBytes,creationTimestamp)" \
        --sort-by=creationTimestamp
    { status=$?; set +x; } 2>/dev/null
	exit $status
fi

timestamp=`date +'%Y%m%d-%H%M%S'`

if [[ $dry_run == "echo" ]]; then
	echo ""
	echo "$appname: this is a DRY RUN, commands are printed, not executed"
	echo ""
fi

set -e   # Exit script immediately after error occurs

if [[ $action == "create" ]]; then

	[[ $dry_run != "echo" ]] && set -x

    # Get live-node scm tracking string (git commit sha) from the source VM
    echo "$appname: getting live-node scm tracking info from $vm_name..."
    livenode_commit_sha=`gcloud compute ssh bvw_admin@$vm_name --command "cd live-node && git describe --always"`
    if [[ -z "$livenode_commit_sha" ]]; then
        echo "$appname: error, cannot get live-node scm tracking info from $vm_name, cannot proceed"
        exit 1
    fi 

    # Get live-app scm tracking string (git commit sha, part of folder name, e.g. live-app-d3ff6b2)
    echo "$appname: getting live-app scm tracking info from $vm_name..."
    liveapp_commit_sha=`gcloud compute ssh bvw_admin@$vm_name --command "ls -ld live-app" | awk '/^.*live-app -> live-app-/{print $NF}' | cut -c 10-16`
    if [[ -z "$liveapp_commit_sha" ]]; then
        echo "$appname: error, cannot get live-app scm tracking info from $vm_name, cannot proceed"
        exit 1
    fi 

    $dry_run ./bvinstances.sh stop $vm_name -f

    image_name="livenode-${livenode_commit_sha}-liveapp-${liveapp_commit_sha}-$timestamp"
    description=$image_name

	# Create new image
	#
	$dry_run gcloud compute images create -q $image_name \
    --project bvc-portal-staging \
	--source-disk=$vm_name \
	--source-disk-zone=$vm_zone \
	--description=$description

	# Replace previous "latest" image with new image
	#
	$dry_run gcloud compute images delete -q livenode-latest \
		--project bvc-portal-staging
	$dry_run gcloud compute images create -q livenode-latest \
		--project bvc-portal-staging \
		--source-image=$image_name \
        --description="source:$image_name"

	# TODO: Replace VM templates with new ones based on new image (this only makes
	# a difference when image size changes, but it could just be done each time)

    { set +x; } 2>/dev/null

elif [[ $action == "publish" ]]; then

    if [[ -z "$image_name" ]]; then
        image_name="livenode-latest"
    fi

	[[ $dry_run != "echo" ]] && set -x

    # First delete "latest" production image
    #
	$dry_run gcloud compute images delete livenode-latest --project bvc-portal -q

	# Copy staging image to "latest" production image name
	#
	$dry_run gcloud compute images create -q \
	    --project=bvc-portal livenode-latest \
	    --source-image=$image_name \
		--source-image-project=bvc-portal-staging \
        --description="source:staging,$image_name"

    { set +x; } 2>/dev/null

elif [[ $action == "delete" ]]; then

    validate_image_name

	[[ $dry_run != "echo" ]] && set -x

    $dry_run gcloud compute images delete $image_name \
        --project bvc-portal-staging
    
    { set +x; } 2>/dev/null
fi


if [[ $dry_run == "echo" ]]; then
	echo ""
	echo "$appname: end of DRY RUN, to execute use --force option"
	echo ""
	echo "$appname: for more info, use --help option"
fi

