# GCP VM Image Management for bvc Live 

## Introduction

The scripts in this repository help manage GCP VM images containing the code &
data that support bvc Live 3D walkthrough property service requests.

The scripts below offer an abstract level of control over the code, instances,
and models needed to realize an image, and provide a reasonable set of operations
to build, test and deploy the system.

Creating and deploying a bvc Windows image is a complex undertaking, as it
involves pulling together different code and executable modules, along with
property models, and performing subjective tests on staging VM instances before
wrapping it all up for production.

The procedures documented below require a number of complicated invocations of
gcloud, gsutil, ssh, and Windows command-line utilities. The scripts do most
of the heavy-lifting


## Target System Structure

A bvc VM image is a Windows Server OS, with the following items:

* C:\Users\bvw_admin account (password in 1Password)
* Setup to autologon to bvw_admin and run startup script upon boot
* `C:\Users\bvw_admin\live-node\...`  JS code pulled from BitBucket
* `C:\Users\bvw_admin\live-app\...`  Unity player build of template + live-app
* `C:\Users\bvw_admin\startup.bat`  Script to run live-node automatically upon boot
* `C:\Users\bvw_admin\builds`  Folder containing property-specific Unity builds, and property id links to each one.

## Prerequisites

* Local installation of gcloud, gsutil
* Git for Windows (if running on a Windows machine locally)

## Scripts, files

* `bvimages.sh - ` Creates and publishes VM images used by above VM instances
* `bvinstances.sh - ` Lists, creates, and deletes VM instances
* `bvzones.sh - ` Lists GCP availability zones with GPUs
* `crontab.txt - ` Manages per-client VM allocations (temporary until dynamic provisioning implemented)
* `bvmodels.sh - ` Manages and deploys property models to staging VM

## Create buildtest GCP VM on staging cloud environment

New VM instances are created with a default template and image, which we incrementally update anytime new live-node, live-app, or property models are available.  We add the updates and test in staging before preparing a new image for production.  The first step is to create a VM in staging:

* Open a Git Bash shell, type in the following:
* 
* `./bvinstances.sh create ln-buildtest-01`

## Update live-node on VM

The live-node service handles communication and startup/shutdown of local live-app sessions. The code repository is: https://bitbucket.org/bvc/live-node/src/main/.  To update, just open a shell onto the remote VM, cd to the live-node working directory, and pull the latest live-node code with git:

1. Open a Git Bash shell, type in the following:
1. `gcloud compute ssh bvw_admin@ln-buildtest-01`
1. `cd live-node`
1. `git pull`

## Update live-app on VM

The live-app program is a Unity player build, that loads and streams 3D property models to WebRTC clients during a bvc Live 3D walkthrough session.  The live-app compressed archives are located in a Google storage bucket: gs://live-app-repo-us/.  To update, open a shell onto the staging VM, download and uncompress a live-app archive, and repoint the live-app link to the new live-app folder.

1. `gcloud compute ssh bview_admin@ln-buildtest-01`
(this opens a new shell window, into it, type the following:
1. `gsutil cp gs://live-walkthrough-repo-us/live-app/live-app-XXXXXX.7z .`
1. `7z x live-app-XXXXXX`
1. `rm live-app`
1. `mklink /d live-app live-app-XXXXXX`

## Add property model(s) to VM. Basic Workflow

### Developer (create and publish build to Google storage)
1. Using unity-dev-tools (https://bitbucket.org/bvc/unity-dev-tools/src/master/BvBuildPlayer/)
1. Create and test Unity build locally with BvBuildAddressables.bat script (in bvw-unity repository)
1. Publish Unity build with BvBuildPublish.bat, which creates a zipped file, uploads to Google storage bucket live-app-repo-us

### DevOps, test build, create VM image
1. Create new VM in staging, download the build to C:\bvw_admin\builds\
1. Unzip file and create a link from propertyId to the build folder
1. Perform QA test on the property from https://staging.bvc.com
1. Run `bvimages.sh create` to create a new image, and replace the "latest" image name
1. Create another new VM in staging, and performs basic tests to ensure proper working order
1. Run `bvimages.sh publish` to copy the image to production
1. Run a sanity check on production

### DevOps Example Procedures

#### Create VM, deploy property build(s)

1. On local machine in this working directory, open a Unix shell (bash on mac, or 'git bash' on Windows)
1. `./bvinstances.sh create ln-buildtest-01`
1. `./bvmodels.sh list`
1. Choose a model from the list, copy the full path (e.g. gs://live-app-repo-us/S2D0a1yzC8s8Mfm37Fv8-alto18_20pinest_newyork-cs41-20230501-153111.7z)
1. `./bvmodels.sh deploy gs://live-app-repo-us/S2D0a1yzC8s8Mfm37Fv8-alto18_20pinest_newyork-cs41-20230501-153111.7z --vm ln-buildtest-01`
1. Repeat as needed for other properties

#### Test the property build(s)

1. On local machine, open browser to https://staging.bvc.com, navigate to property matching the build id (in this case JF0FT0AdOJWvmTfvubYW is the Healthpeak 100 Acorn Park Dr property)
1. Select "Live Walkthrough", notice Unity startup in remote desktop, wait for scene to appear, QC the live UX for that property.

#### Create new image, sanity-check it on a new VM

1. `./bvimages.sh create --vm ln-buildtest-01`      (this automatically stops the instance)
1. `./bvinstances.sh create ln-buildtest-02`
1. TEST: (same to above, just basic sanity check of Live Walkthrough on a few properties to ensure the image works)

#### Publish Build to production

1. `.\bvimages.sh publish`
1. On local browser, visit https://portal.bvc.com, run same test as above

#### Rollback

Any image can be copied to the `livenode-latest` name used by the VM templates, so to rollback, simply choose a previous image from the list, and copy it to the name (staging), or publish it (production).

##### Get List of staging images

```
./bvimages.sh list
NAME                                 DESCRIPTION
lni-20220928-185911-06062e7-6-props  live-node-sha=06062e7,bvw-unity-cs=5343-5477-5548-5614-5654-5558
lni-20220928-234817-06062e7-6-props  live-node-sha=06062e7,bvw-unity-cs=5343-5477-5548-5614-5654-5658
lni-20221003-090523-06062e7          ln-sha-06062e7,prop-cs-5343-5477-5548-5614-5654-5658
livenode-latest                      source:lni-20221003-090523-06062e7
```

##### Rollback Staging

```
gcloud compute images delete livenode-latest --project=bvc-portal-staging
gcloud compute images create -q livenode-latest --project bvc-portal-staging --source-image=lni-20220928-234817-06062e7-6-props  --description=source:lni-20220928-234817-06062e7-6-props
```

##### Rollback Production

`./bvimages.sh publish --name lni-20220928-234817-06062e7-6-props`