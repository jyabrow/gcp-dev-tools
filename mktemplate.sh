#!/bin/bash

gcloud compute instance-templates create instance-template-1 \
	--project=bvc-portal-staging \
	--machine-type=n1-standard-8 \
	--network-interface=network=default,network-tier=PREMIUM \
	--maintenance-policy=TERMINATE \
	--provisioning-model=STANDARD \
	--service-account=189043980068-compute@developer.gserviceaccount.com \
	--scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
	--accelerator=count=1,type=nvidia-tesla-t4 \
	--enable-display-device \
	--tags=http-server,https-server \
	--create-disk=auto-delete=yes,boot=yes,device-name=instance-template-1,image=projects/bvc-portal-staging/global/images/livenode-latest,mode=rw,size=100,type=pd-balanced \
	--no-shielded-secure-boot \
	--shielded-vtpm \
	--shielded-integrity-monitoring \
	--reservation-affinity=any
